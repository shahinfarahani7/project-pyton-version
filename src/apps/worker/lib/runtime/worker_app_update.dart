import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../api/worker_routes.dart';
import '../config/worker_config.dart';

/// Version installed on this device. [versionCode] is the Android build number.
class InstalledAppVersion {
  const InstalledAppVersion({
    required this.versionName,
    required this.versionCode,
  });

  final String versionName;
  final int versionCode;
}

enum WorkerAppUpdatePhase { idle, available, downloading, installing, failed }

enum WorkerAppInstallPrompt { installerLaunched, permissionRequired }

class WorkerAppUpdateException implements Exception {
  const WorkerAppUpdateException(this.code, [this.detail]);

  final String code;
  final String? detail;

  @override
  String toString() => 'WorkerAppUpdateException($code, $detail)';
}

class WorkerAppRelease {
  const WorkerAppRelease({
    required this.versionName,
    required this.versionCode,
    required this.downloadPath,
    required this.sha256,
    required this.sizeBytes,
    this.notes,
    this.mandatory = false,
  });

  final String versionName;
  final int versionCode;
  final String downloadPath;
  final String sha256;
  final int sizeBytes;
  final String? notes;
  final bool mandatory;

  factory WorkerAppRelease.fromJson(Map<String, dynamic> json) {
    final versionName = json['versionName'];
    final versionCode = json['versionCode'];
    final downloadPath = json['downloadPath'];
    final sha256Hex = json['sha256'];
    final sizeBytes = json['sizeBytes'];
    if (versionName is! String || versionName.isEmpty) {
      throw const FormatException('versionName');
    }
    if (versionCode is! int || versionCode <= 0) {
      throw const FormatException('versionCode');
    }
    if (downloadPath is! String ||
        downloadPath != WorkerRoutes.workerAppReleaseApk) {
      throw const FormatException('downloadPath');
    }
    if (sha256Hex is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256Hex)) {
      throw const FormatException('sha256');
    }
    if (sizeBytes is! int || sizeBytes <= 0) {
      throw const FormatException('sizeBytes');
    }
    final notes = json['notes'];
    if (notes != null && notes is! String) {
      throw const FormatException('notes');
    }
    final mandatory = json['mandatory'];
    if (mandatory != null && mandatory is! bool) {
      throw const FormatException('mandatory');
    }
    return WorkerAppRelease(
      versionName: versionName,
      versionCode: versionCode,
      downloadPath: downloadPath,
      sha256: sha256Hex,
      sizeBytes: sizeBytes,
      notes: notes is String && notes.isNotEmpty ? notes : null,
      mandatory: mandatory == true,
    );
  }
}

bool workerAppReleaseIsNewer({
  required InstalledAppVersion installed,
  required WorkerAppRelease release,
}) {
  return release.versionCode > installed.versionCode;
}

String workerAppUpdateUserMessage(WorkerAppUpdateException error) {
  return switch (error.code) {
    'RELEASE_HASH_MISMATCH' =>
      'The downloaded update did not match the published checksum.',
    'RELEASE_SIZE_MISMATCH' => 'The downloaded update was incomplete.',
    'RELEASE_DOWNLOAD_FAILED' => 'The update download failed.',
    'RELEASE_HOST_MISMATCH' =>
      'The update address is not on this worker server.',
    'UPDATE_DIRECTORY_UNAVAILABLE' => 'This device cannot store the update.',
    'INSTALL_PERMISSION_REQUIRED' =>
      'Allow this app to install updates, then tap Update again.',
    _ => 'Could not install the update.',
  };
}

Uri workerAppReleaseDownloadUri({
  required WorkerConfig config,
  required WorkerAppRelease release,
}) {
  final uri = config.resolve(release.downloadPath);
  final expected = config.resolve(WorkerRoutes.workerAppReleaseApk);
  if (uri.scheme != expected.scheme ||
      uri.host != expected.host ||
      uri.port != expected.port ||
      uri.path != expected.path) {
    throw const WorkerAppUpdateException('RELEASE_HOST_MISMATCH');
  }
  return uri;
}

WorkerAppInstallPrompt parseWorkerAppInstallPrompt(String? raw) {
  return switch (raw) {
    'installerLaunched' => WorkerAppInstallPrompt.installerLaunched,
    'permissionRequired' => WorkerAppInstallPrompt.permissionRequired,
    _ => throw const WorkerAppUpdateException('INSTALL_PROMPT_UNKNOWN'),
  };
}

/// Downloads the published APK from the configured worker server and checks its checksum.
Future<File> downloadWorkerAppRelease({
  required WorkerConfig config,
  required WorkerAppRelease release,
  required Directory destinationDirectory,
  required http.Client client,
  void Function(double progress)? onProgress,
}) async {
  final uri = workerAppReleaseDownloadUri(config: config, release: release);
  http.StreamedResponse? response;
  IOSink? sink;
  File? partial;
  try {
    response = await client.send(http.Request('GET', uri));
    if (response.statusCode != 200) {
      throw WorkerAppUpdateException(
        'RELEASE_DOWNLOAD_FAILED',
        '${response.statusCode}',
      );
    }
    final advertised = response.contentLength;
    if (advertised != null && advertised != release.sizeBytes) {
      throw const WorkerAppUpdateException('RELEASE_SIZE_MISMATCH');
    }
    await destinationDirectory.create(recursive: true);
    partial = File.fromUri(
      destinationDirectory.uri.resolve('worker-update.apk.partial'),
    );
    final target = File.fromUri(
      destinationDirectory.uri.resolve('worker-update.apk'),
    );
    if (partial.existsSync()) {
      await partial.delete();
    }
    sink = partial.openWrite();
    final digestSink = _DigestSink();
    final converter = sha256.startChunkedConversion(digestSink);
    var written = 0;
    await for (final chunk in response.stream) {
      written += chunk.length;
      if (written > release.sizeBytes) {
        throw const WorkerAppUpdateException('RELEASE_SIZE_MISMATCH');
      }
      converter.add(chunk);
      sink.add(chunk);
      onProgress?.call(written / release.sizeBytes);
    }
    await sink.flush();
    await sink.close();
    sink = null;
    converter.close();
    if (written != release.sizeBytes) {
      throw const WorkerAppUpdateException('RELEASE_SIZE_MISMATCH');
    }
    if (digestSink.value?.toString() != release.sha256) {
      throw const WorkerAppUpdateException('RELEASE_HASH_MISMATCH');
    }
    if (target.existsSync()) {
      await target.delete();
    }
    return partial.rename(target.path);
  } on WorkerAppUpdateException {
    await _discardUpdateDownload(
      response: response,
      sink: sink,
      partial: partial,
    );
    rethrow;
  } catch (error) {
    await _discardUpdateDownload(
      response: response,
      sink: sink,
      partial: partial,
    );
    throw WorkerAppUpdateException('RELEASE_DOWNLOAD_FAILED', '$error');
  }
}

Future<void> _discardUpdateDownload({
  required http.StreamedResponse? response,
  required IOSink? sink,
  required File? partial,
}) async {
  try {
    await response?.stream.drain<void>();
  } catch (_) {}
  try {
    await sink?.close();
  } catch (_) {}
  if (partial != null && partial.existsSync()) {
    await partial.delete();
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}
