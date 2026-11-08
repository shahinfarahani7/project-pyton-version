import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../api/worker_routes.dart';
import '../config/worker_config.dart';
import '../models/worker_model_catalog.dart';

/// Version installed on this device. [versionCode] is the Android build number.
class InstalledAppVersion {
  const InstalledAppVersion({
    required this.versionName,
    required this.versionCode,
  });

  final String versionName;
  final int versionCode;
}

enum WorkerUpdateTarget { application, model }

enum WorkerAppUpdatePhase { idle, available, downloading, installing, failed }

const installedModelShaStoreKey = 'worker.installed-model-sha256';

const modelUpdateNeedsNewerAppMessage =
    'Install the app update first.';

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

class WorkerModelRelease {
  const WorkerModelRelease({
    required this.modelVersionId,
    required this.artifactSha256,
    required this.fileName,
    this.notes,
  });

  final String modelVersionId;
  final String artifactSha256;
  final String fileName;
  final String? notes;

  /// True when this app build already knows how to install the published model.
  bool get canInstallOnThisApp {
    if (modelVersionId == WorkerModelCatalog.modelVersionId &&
        fileName == WorkerModelCatalog.fileName &&
        artifactSha256 == WorkerModelCatalog.knownGeneralArtifactSha256) {
      return true;
    }
    return modelVersionId == WorkerModelCatalog.gpuModelVersionId &&
        fileName == WorkerModelCatalog.gpuFileName &&
        artifactSha256 == WorkerModelCatalog.knownGpuArtifactSha256;
  }

  factory WorkerModelRelease.fromJson(Map<String, dynamic> json) {
    final modelVersionId = json['modelVersionId'];
    final artifactSha256 = json['artifactSha256'];
    final fileName = json['fileName'];
    if (modelVersionId is! String ||
        modelVersionId.isEmpty ||
        modelVersionId.contains('/') ||
        modelVersionId.contains('\\')) {
      throw const FormatException('modelVersionId');
    }
    if (artifactSha256 is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(artifactSha256)) {
      throw const FormatException('artifactSha256');
    }
    if (fileName is! String ||
        fileName.isEmpty ||
        fileName.contains('/') ||
        fileName.contains('\\')) {
      throw const FormatException('fileName');
    }
    final notes = json['notes'];
    if (notes != null && notes is! String) {
      throw const FormatException('notes');
    }
    return WorkerModelRelease(
      modelVersionId: modelVersionId,
      artifactSha256: artifactSha256,
      fileName: fileName,
      notes: notes is String && notes.isNotEmpty ? notes : null,
    );
  }
}

class WorkerUpdateCatalog {
  const WorkerUpdateCatalog({this.application, this.model});

  final WorkerAppRelease? application;
  final WorkerModelRelease? model;

  factory WorkerUpdateCatalog.fromJson(Map<String, dynamic> json) {
    final updates = json['updates'];
    if (updates is List) {
      WorkerAppRelease? application;
      WorkerModelRelease? model;
      for (final item in updates) {
        if (item is! Map) {
          throw const FormatException('updates');
        }
        final parsed = WorkerUpdateCatalog.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (parsed.application != null) {
          if (application != null) {
            throw const FormatException('updates');
          }
          application = parsed.application;
        }
        if (parsed.model != null) {
          if (model != null) {
            throw const FormatException('updates');
          }
          model = parsed.model;
        }
      }
      if (application == null && model == null) {
        throw const FormatException('updates');
      }
      return WorkerUpdateCatalog(application: application, model: model);
    }
    final target = json['target'] ?? 'application';
    if (target == 'application') {
      return WorkerUpdateCatalog(application: WorkerAppRelease.fromJson(json));
    }
    if (target == 'model') {
      return WorkerUpdateCatalog(model: WorkerModelRelease.fromJson(json));
    }
    throw const FormatException('target');
  }
}

class WorkerUpdateDecision {
  const WorkerUpdateDecision({this.application, this.model});

  final WorkerAppRelease? application;
  final WorkerModelRelease? model;
}

WorkerUpdateDecision decideWorkerUpdates({
  required WorkerUpdateCatalog catalog,
  required InstalledAppVersion? installedApp,
  required String? installedModelSha256,
  required bool modelReady,
}) {
  final publishedApp = catalog.application;
  final application =
      publishedApp != null &&
          installedApp != null &&
          workerAppReleaseIsNewer(installed: installedApp, release: publishedApp)
      ? publishedApp
      : null;
  final publishedModel = catalog.model;
  final model =
      publishedModel != null &&
          workerModelReleaseNeedsInstall(
            release: publishedModel,
            installedArtifactSha256: installedModelSha256,
            modelReady: modelReady,
          )
      ? publishedModel
      : null;
  return WorkerUpdateDecision(application: application, model: model);
}

bool workerModelReleaseNeedsInstall({
  required WorkerModelRelease release,
  required String? installedArtifactSha256,
  required bool modelReady,
}) {
  if (!release.canInstallOnThisApp) {
    return true;
  }
  if (!modelReady) {
    return true;
  }
  if (installedArtifactSha256 == null || installedArtifactSha256.isEmpty) {
    return false;
  }
  return installedArtifactSha256 != release.artifactSha256;
}

/// The blocking model dialog is only for a missing model when nothing was published.
/// An application release must not be presented as a model update.
bool shouldShowUnpublishedModelDownloadPrompt({
  required bool applicationUpdateOffered,
  required bool modelUpdateOffered,
  required bool modelReady,
  required bool modelTransferActive,
}) {
  if (applicationUpdateOffered || modelUpdateOffered) {
    return false;
  }
  if (modelReady || modelTransferActive) {
    return false;
  }
  return true;
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

File workerAppUpdateApkFile(Directory directory) {
  return File.fromUri(directory.uri.resolve('worker-update.apk'));
}

/// A finished download that still matches the published release.
///
/// A failed install leaves this file in place so the next attempt can open
/// the installer again without downloading it.
Future<File?> verifiedWorkerAppUpdateFile({
  required Directory directory,
  required WorkerAppRelease release,
}) async {
  final file = workerAppUpdateApkFile(directory);
  if (!file.existsSync()) {
    return null;
  }
  if (await file.length() != release.sizeBytes) {
    return null;
  }
  final digest = sha256.convert(await file.readAsBytes()).toString();
  if (digest != release.sha256) {
    return null;
  }
  return file;
}

Future<void> deleteDownloadedWorkerAppUpdate(Directory directory) async {
  final file = workerAppUpdateApkFile(directory);
  if (file.existsSync()) {
    await file.delete();
  }
  final partial = File.fromUri(
    directory.uri.resolve('worker-update.apk.partial'),
  );
  if (partial.existsSync()) {
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
