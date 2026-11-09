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

/// An update published on Google Play for this install.
class PlayAppUpdateOffer {
  const PlayAppUpdateOffer({
    required this.available,
    this.versionCode = 0,
    this.immediateAllowed = false,
    this.flexibleAllowed = false,
    this.downloaded = false,
    this.inProgress = false,
  });

  final bool available;
  final int versionCode;
  final bool immediateAllowed;
  final bool flexibleAllowed;
  final bool downloaded;
  final bool inProgress;

  /// `null` when Play could not be asked, so a previous offer stays in place.
  static PlayAppUpdateOffer? fromMap(Map<Object?, Object?> raw) {
    if (raw['known'] == false) {
      return null;
    }
    final versionCode = raw['versionCode'];
    return PlayAppUpdateOffer(
      available: raw['available'] == true,
      versionCode: versionCode is int
          ? versionCode
          : versionCode is num
          ? versionCode.toInt()
          : 0,
      immediateAllowed: raw['immediateAllowed'] == true,
      flexibleAllowed: raw['flexibleAllowed'] == true,
      downloaded: raw['downloaded'] == true,
      inProgress: raw['inProgress'] == true,
    );
  }
}

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
    'RELEASE_DOWNLOAD_FAILED' =>
      'The update download stopped. Saved progress was kept. Tap Update again to continue.',
    'RELEASE_RESUME_REJECTED' =>
      'The update server could not continue the saved download.',
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

/// Bytes already stored for an interrupted update download.
Future<int> savedWorkerAppUpdateBytes(Directory directory) async {
  final partial = _workerAppUpdatePartialFile(directory);
  if (!partial.existsSync()) {
    return 0;
  }
  return partial.length();
}

/// Downloads the published APK and checks its checksum.
///
/// A dropped connection leaves `worker-update.apk.partial` in place. The next
/// call asks the server for the remaining bytes and appends them.
Future<File> downloadWorkerAppRelease({
  required WorkerConfig config,
  required WorkerAppRelease release,
  required Directory destinationDirectory,
  required http.Client client,
  void Function(double progress)? onProgress,
}) async {
  final uri = workerAppReleaseDownloadUri(config: config, release: release);
  await destinationDirectory.create(recursive: true);
  final partial = _workerAppUpdatePartialFile(destinationDirectory);
  final target = workerAppUpdateApkFile(destinationDirectory);
  var offset = partial.existsSync() ? await partial.length() : 0;
  if (offset > release.sizeBytes) {
    await partial.delete();
    offset = 0;
  }
  if (offset == release.sizeBytes) {
    if (await _sha256File(partial) == release.sha256) {
      if (target.existsSync()) {
        await target.delete();
      }
      return partial.rename(target.path);
    }
    await partial.delete();
    offset = 0;
  }

  http.StreamedResponse? response;
  RandomAccessFile? output;
  var discardPartial = false;
  try {
    final request = http.Request('GET', uri);
    request.headers['accept-encoding'] = 'identity';
    if (offset > 0) {
      request.headers['range'] = 'bytes=$offset-';
    }
    response = await client.send(request);
    final status = response.statusCode;
    if (status == 416) {
      discardPartial = true;
      throw const WorkerAppUpdateException('RELEASE_SIZE_MISMATCH');
    }
    if (offset > 0 && status == 200) {
      throw const WorkerAppUpdateException('RELEASE_RESUME_REJECTED');
    }
    if ((offset == 0 && status != 200) || (offset > 0 && status != 206)) {
      throw WorkerAppUpdateException('RELEASE_DOWNLOAD_FAILED', '$status');
    }
    var end = release.sizeBytes - 1;
    if (status == 206) {
      final header = response.headers['content-range'];
      final match = RegExp(
        r'^bytes (\d+)-(\d+)/(\d+)$',
      ).firstMatch(header ?? '');
      if (match == null ||
          int.parse(match.group(1)!) != offset ||
          int.parse(match.group(3)!) != release.sizeBytes) {
        throw const WorkerAppUpdateException('RELEASE_RESUME_REJECTED');
      }
      end = int.parse(match.group(2)!);
      if (end < offset || end >= release.sizeBytes) {
        throw const WorkerAppUpdateException('RELEASE_RESUME_REJECTED');
      }
    } else {
      final advertised = response.contentLength;
      if (advertised != null && advertised != release.sizeBytes) {
        throw const WorkerAppUpdateException('RELEASE_SIZE_MISMATCH');
      }
    }
    final expectedBody = end - offset + 1;
    final advertisedBody = response.contentLength;
    if (advertisedBody != null && advertisedBody != expectedBody) {
      throw const WorkerAppUpdateException('RELEASE_SIZE_MISMATCH');
    }
    output = await partial.open(mode: FileMode.append);
    var written = offset;
    await for (final chunk in response.stream) {
      if (written + chunk.length > end + 1) {
        discardPartial = true;
        throw const WorkerAppUpdateException('RELEASE_SIZE_MISMATCH');
      }
      await output.writeFrom(chunk);
      written += chunk.length;
      onProgress?.call(written / release.sizeBytes);
    }
    await output.flush();
    await output.close();
    output = null;
    if (written != release.sizeBytes) {
      throw const WorkerAppUpdateException(
        'RELEASE_DOWNLOAD_FAILED',
        'incomplete',
      );
    }
    if (await _sha256File(partial) != release.sha256) {
      discardPartial = true;
      throw const WorkerAppUpdateException('RELEASE_HASH_MISMATCH');
    }
    if (target.existsSync()) {
      await target.delete();
    }
    return partial.rename(target.path);
  } on WorkerAppUpdateException {
    await _closeUpdateDownload(response: response, output: output);
    if (discardPartial && partial.existsSync()) {
      await partial.delete();
    }
    rethrow;
  } catch (error) {
    await _closeUpdateDownload(response: response, output: output);
    throw WorkerAppUpdateException('RELEASE_DOWNLOAD_FAILED', '$error');
  }
}

Future<void> _closeUpdateDownload({
  required http.StreamedResponse? response,
  required RandomAccessFile? output,
}) async {
  try {
    await response?.stream.drain<void>();
  } catch (_) {}
  if (output == null) {
    return;
  }
  try {
    await output.flush();
  } catch (_) {}
  try {
    await output.close();
  } catch (_) {}
}

File _workerAppUpdatePartialFile(Directory directory) {
  return File.fromUri(directory.uri.resolve('worker-update.apk.partial'));
}

Future<String> _sha256File(File file) async {
  final digestSink = _DigestSink();
  final converter = sha256.startChunkedConversion(digestSink);
  await for (final chunk in file.openRead()) {
    converter.add(chunk);
  }
  converter.close();
  final value = digestSink.value;
  if (value == null) {
    throw const WorkerAppUpdateException('RELEASE_HASH_MISMATCH');
  }
  return value.toString();
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
  final partial = _workerAppUpdatePartialFile(directory);
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
