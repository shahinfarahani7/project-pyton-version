import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:edgemint_worker/config/worker_config.dart';
import 'package:edgemint_worker/models/worker_model_catalog.dart';
import 'package:edgemint_worker/platform/worker_runtime_channel.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/runtime/worker_app_update.dart';
import 'package:edgemint_worker/worker_app_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const installed = InstalledAppVersion(
    versionName: '5.0.0',
    versionCode: 40100,
  );

  WorkerAppRelease release({
    int versionCode = 40200,
    String versionName = '5.1.0',
    String? sha256Hex,
    int? sizeBytes,
    String downloadPath = '/worker-app/release/apk',
    bool mandatory = false,
  }) {
    return WorkerAppRelease.fromJson({
      'versionName': versionName,
      'versionCode': versionCode,
      'downloadPath': downloadPath,
      'sha256': sha256Hex ?? 'ab' * 32,
      'sizeBytes': sizeBytes ?? 12,
      'notes': 'Fixes startup',
      'mandatory': mandatory,
    });
  }

  test('a model release updates the model and an app release updates the app', () {
    final catalogSha = WorkerModelCatalog.knownGeneralArtifactSha256;
    final currentModel = WorkerModelRelease(
      modelVersionId: WorkerModelCatalog.modelVersionId,
      artifactSha256: catalogSha,
      fileName: WorkerModelCatalog.fileName,
    );
    final unknownModel = WorkerModelRelease(
      modelVersionId: 'mdv_other',
      artifactSha256: 'cd' * 32,
      fileName: 'other.litertlm',
    );
    final newerApp = release();

    final sameModel = decideWorkerUpdates(
      catalog: WorkerUpdateCatalog(model: currentModel),
      installedApp: installed,
      installedModelSha256: null,
      modelReady: true,
    );
    expect(sameModel.application, isNull);
    expect(sameModel.model, isNull);

    final missingModel = decideWorkerUpdates(
      catalog: WorkerUpdateCatalog(model: currentModel),
      installedApp: installed,
      installedModelSha256: null,
      modelReady: false,
    );
    expect(missingModel.model, currentModel);
    expect(missingModel.application, isNull);

    final replacedModel = decideWorkerUpdates(
      catalog: WorkerUpdateCatalog(model: currentModel),
      installedApp: installed,
      installedModelSha256: '12' * 32,
      modelReady: true,
    );
    expect(replacedModel.model, currentModel);

    final needsApp = decideWorkerUpdates(
      catalog: WorkerUpdateCatalog(model: unknownModel, application: newerApp),
      installedApp: installed,
      installedModelSha256: catalogSha,
      modelReady: true,
    );
    expect(needsApp.application, newerApp);
    expect(needsApp.model, unknownModel);
    expect(unknownModel.canInstallOnThisApp, isFalse);
    expect(currentModel.canInstallOnThisApp, isTrue);
  });

  test('an application release does not prompt a model update', () {
    final decision = decideWorkerUpdates(
      catalog: WorkerUpdateCatalog(application: release()),
      installedApp: installed,
      installedModelSha256: null,
      modelReady: false,
    );
    expect(decision.application, isNotNull);
    expect(decision.model, isNull);
    expect(
      shouldShowUnpublishedModelDownloadPrompt(
        applicationUpdateOffered: decision.application != null,
        modelUpdateOffered: decision.model != null,
        modelReady: false,
        modelTransferActive: false,
      ),
      isFalse,
    );
  });

  test('a higher build number is an update and the same build is not', () {
    expect(
      workerAppReleaseIsNewer(installed: installed, release: release()),
      isTrue,
    );
    expect(
      workerAppReleaseIsNewer(
        installed: installed,
        release: release(versionCode: 40100, versionName: '5.0.0'),
      ),
      isFalse,
    );
    expect(
      workerAppReleaseIsNewer(
        installed: installed,
        release: release(versionCode: 40000, versionName: '4.9.0'),
      ),
      isFalse,
    );
  });

  test('release catalog rejects a foreign download address and a bad checksum', () {
    expect(
      () => release(downloadPath: 'https://evil.example/worker.apk'),
      throwsFormatException,
    );
    expect(() => release(sha256Hex: 'ABCD' * 16), throwsFormatException);
    expect(() => release(versionCode: 0), throwsFormatException);
    expect(() => release(sizeBytes: 0), throwsFormatException);
  });

  test('download keeps the apk only when the checksum matches', () async {
    final bytes = utf8.encode('worker-apk');
    final digest = sha256.convert(bytes).toString();
    final dir = await Directory.systemTemp.createTemp('worker-app-update');
    addTearDown(() async {
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    });
    final config = WorkerConfig(baseUrl: Uri.parse('http://10.0.2.2:8081'));

    final accepted = MockClient.streaming((request, _) async {
      expect(
        request.url,
        Uri.parse('http://10.0.2.2:8081/worker-app/release/apk'),
      );
      return http.StreamedResponse(
        Stream<List<int>>.value(bytes),
        200,
        contentLength: bytes.length,
      );
    });
    addTearDown(accepted.close);
    final file = await downloadWorkerAppRelease(
      config: config,
      release: release(sha256Hex: digest, sizeBytes: bytes.length),
      destinationDirectory: dir,
      client: accepted,
    );
    expect(await file.readAsBytes(), bytes);
    expect(file.uri.pathSegments.last, 'worker-update.apk');

    final rejected = MockClient.streaming((request, _) async {
      return http.StreamedResponse(
        Stream<List<int>>.value(bytes),
        200,
        contentLength: bytes.length,
      );
    });
    addTearDown(rejected.close);
    await expectLater(
      downloadWorkerAppRelease(
        config: config,
        release: release(sha256Hex: '0' * 64, sizeBytes: bytes.length),
        destinationDirectory: dir,
        client: rejected,
      ),
      throwsA(
        isA<WorkerAppUpdateException>().having(
          (error) => error.code,
          'code',
          'RELEASE_HASH_MISMATCH',
        ),
      ),
    );
    expect(
      File.fromUri(dir.uri.resolve('worker-update.apk.partial')).existsSync(),
      isFalse,
    );
  });

  test('a dropped download keeps its bytes and the next attempt continues', () async {
    final bytes = utf8.encode('worker-update-bytes');
    final digest = sha256.convert(bytes).toString();
    final dir = await Directory.systemTemp.createTemp('worker-app-update-resume');
    addTearDown(() async {
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    });
    final config = WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8081'));
    final published = release(sha256Hex: digest, sizeBytes: bytes.length);
    var calls = 0;
    final client = MockClient.streaming((request, _) async {
      calls += 1;
      if (calls == 1) {
        return http.StreamedResponse(
          Stream<List<int>>.value(bytes.sublist(0, 6)),
          200,
          contentLength: bytes.length,
        );
      }
      expect(request.headers['range'], 'bytes=6-');
      final rest = bytes.sublist(6);
      return http.StreamedResponse(
        Stream<List<int>>.value(rest),
        206,
        contentLength: rest.length,
        headers: {
          'content-range': 'bytes 6-${bytes.length - 1}/${bytes.length}',
        },
      );
    });
    addTearDown(client.close);

    await expectLater(
      downloadWorkerAppRelease(
        config: config,
        release: published,
        destinationDirectory: dir,
        client: client,
      ),
      throwsA(
        isA<WorkerAppUpdateException>().having(
          (error) => error.code,
          'code',
          'RELEASE_DOWNLOAD_FAILED',
        ),
      ),
    );
    final partial = File.fromUri(dir.uri.resolve('worker-update.apk.partial'));
    expect(partial.existsSync(), isTrue);
    expect(await partial.readAsBytes(), bytes.sublist(0, 6));

    final file = await downloadWorkerAppRelease(
      config: config,
      release: published,
      destinationDirectory: dir,
      client: client,
    );
    expect(calls, 2);
    expect(await file.readAsBytes(), bytes);
    expect(partial.existsSync(), isFalse);
  });

  test('a server that ignores Range keeps the saved bytes', () async {
    final bytes = utf8.encode('worker-update-bytes');
    final dir = await Directory.systemTemp.createTemp('worker-app-update-no-range');
    addTearDown(() async {
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    });
    final partial = File.fromUri(dir.uri.resolve('worker-update.apk.partial'));
    await partial.writeAsBytes(bytes.sublist(0, 6));
    final client = MockClient.streaming((request, _) async {
      expect(request.headers['range'], 'bytes=6-');
      return http.StreamedResponse(
        Stream<List<int>>.value(bytes),
        200,
        contentLength: bytes.length,
      );
    });
    addTearDown(client.close);

    await expectLater(
      downloadWorkerAppRelease(
        config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8081')),
        release: release(sha256Hex: 'ab' * 32, sizeBytes: bytes.length),
        destinationDirectory: dir,
        client: client,
      ),
      throwsA(
        isA<WorkerAppUpdateException>().having(
          (error) => error.code,
          'code',
          'RELEASE_RESUME_REJECTED',
        ),
      ),
    );
    expect(await partial.readAsBytes(), bytes.sublist(0, 6));
  });

  test('controller shows a newer release and installs the verified apk', () async {
    final bytes = utf8.encode('worker-apk');
    final digest = sha256.convert(bytes).toString();
    final dir = await Directory.systemTemp.createTemp('worker-app-update-controller');
    addTearDown(() async {
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    });
    final platform = NoopWorkerRuntimeChannel(
      installedAppVersion: installed,
      storePath: dir.path,
    );
    final client = MockClient((request) async {
      if (request.url.path == '/worker-app/release') {
        return http.Response(
          jsonEncode({
            'versionName': '5.1.0',
            'versionCode': 40200,
            'downloadPath': '/worker-app/release/apk',
            'sha256': digest,
            'sizeBytes': bytes.length,
            'notes': 'Fixes startup',
            'mandatory': false,
          }),
          200,
        );
      }
      if (request.url.path == '/worker-app/release/apk') {
        return http.Response.bytes(bytes, 200);
      }
      return http.Response('missing', 404);
    });
    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8081')),
      httpClient: client,
      platform: platform,
      encryptedStore: InMemoryEncryptedStore(),
    );
    addTearDown(controller.dispose);

    await controller.refreshAppUpdate();
    expect(controller.showsAppUpdateCard, isTrue);
    expect(controller.appUpdateVersionName, '5.1.0');
    expect(controller.appUpdateNotes, 'Fixes startup');
    expect(controller.appUpdatePhase, WorkerAppUpdatePhase.available);
    expect(controller.appUpdateMandatory, isTrue);
    expect(controller.blocksAppUntilUpdate, isTrue);

    await controller.installOfferedAppUpdate();
    expect(platform.installedApkPath, endsWith('worker-update.apk'));
    expect(controller.appUpdatePhase, WorkerAppUpdatePhase.available);
    expect(controller.appUpdateError, isNull);
    expect(
      controller.appUpdateNotice,
      'Confirm the install screen to finish the update.',
    );
    expect(
      await File(platform.installedApkPath!).readAsBytes(),
      bytes,
    );
  });

  test('a failed install keeps the apk and the installed version removes it', () async {
    final bytes = utf8.encode('worker-apk');
    final digest = sha256.convert(bytes).toString();
    final dir = await Directory.systemTemp.createTemp('worker-app-update-keep');
    addTearDown(() async {
      if (!dir.existsSync()) {
        return;
      }
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // The temp directory can disappear while Windows is still releasing it.
      }
    });
    var downloads = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/worker-app/release') {
        return http.Response(
          jsonEncode({
            'versionName': '5.1.0',
            'versionCode': 40200,
            'downloadPath': '/worker-app/release/apk',
            'sha256': digest,
            'sizeBytes': bytes.length,
            'notes': 'Fixes startup',
            'mandatory': true,
          }),
          200,
        );
      }
      if (request.url.path == '/worker-app/release/apk') {
        downloads += 1;
        return http.Response.bytes(bytes, 200);
      }
      return http.Response('missing', 404);
    });
    final platform = _InstallGateChannel(storePath: dir.path);
    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8081')),
      httpClient: client,
      platform: platform,
      encryptedStore: InMemoryEncryptedStore(),
    );
    addTearDown(controller.dispose);

    await controller.refreshAppUpdate();
    platform.failInstall = true;
    await controller.installOfferedAppUpdate();
    final apk = File(
      '${dir.path}${Platform.pathSeparator}app-updates${Platform.pathSeparator}worker-update.apk',
    );
    expect(controller.appUpdatePhase, WorkerAppUpdatePhase.failed);
    expect(apk.existsSync(), isTrue);
    expect(downloads, 1);

    platform.failInstall = false;
    await controller.installOfferedAppUpdate();
    expect(downloads, 1);
    expect(apk.existsSync(), isTrue);
    expect(controller.appUpdatePhase, WorkerAppUpdatePhase.available);

    platform.installed = const InstalledAppVersion(
      versionName: '5.1.0',
      versionCode: 40200,
    );
    await controller.refreshAppUpdate();
    expect(controller.showsAppUpdateCard, isFalse);
    expect(apk.existsSync(), isFalse);
    expect(controller.installedAppVersionName, '5.1.0');
  });

  test('controller refreshes the model and does not install an apk', () async {
    final platform = NoopWorkerRuntimeChannel(installedAppVersion: installed);
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'target': 'model',
          'modelVersionId': WorkerModelCatalog.modelVersionId,
          'artifactSha256': WorkerModelCatalog.knownGeneralArtifactSha256,
          'fileName': WorkerModelCatalog.fileName,
          'notes': 'Refresh Gemma',
        }),
        200,
      );
    });
    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8081')),
      httpClient: client,
      platform: platform,
      encryptedStore: InMemoryEncryptedStore(),
    );
    addTearDown(controller.dispose);

    await controller.refreshAppUpdate();
    expect(controller.showsAppUpdateCard, isFalse);
    expect(controller.showsModelUpdateCard, isTrue);
    expect(controller.modelUpdateNeedsNewerApp, isFalse);

    controller.usesDevMockInference = true;
    await controller.installOfferedModelUpdate();
    expect(platform.installedApkPath, isNull);
    expect(controller.isGemmaReady, isTrue);
    expect(controller.showsModelUpdateCard, isFalse);
  });

  test('controller hides the card when the server has no newer build', () async {
    final dir = await Directory.systemTemp.createTemp('worker-app-update-current');
    addTearDown(() async {
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    });
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'versionName': '5.0.0',
          'versionCode': 40100,
          'downloadPath': '/worker-app/release/apk',
          'sha256': 'ab' * 32,
          'sizeBytes': 4,
        }),
        200,
      );
    });
    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8081')),
      httpClient: client,
      platform: NoopWorkerRuntimeChannel(installedAppVersion: installed),
      encryptedStore: InMemoryEncryptedStore(),
    );
    addTearDown(controller.dispose);

    await controller.refreshAppUpdate();
    expect(controller.showsAppUpdateCard, isFalse);

    controller.appUpdatePhase = WorkerAppUpdatePhase.available;
    controller.appUpdateVersionName = '9.0.0';
    final missing = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8081')),
      httpClient: MockClient((request) async => http.Response('none', 404)),
      platform: NoopWorkerRuntimeChannel(installedAppVersion: installed),
      encryptedStore: InMemoryEncryptedStore(),
    );
    addTearDown(missing.dispose);
    missing.appUpdatePhase = WorkerAppUpdatePhase.available;
    missing.appUpdateVersionName = '9.0.0';
    await missing.refreshAppUpdate();
    expect(missing.showsAppUpdateCard, isFalse);
  });

  test('a Google Play update opens Play and does not download an apk', () async {
    var downloads = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/worker-app/release/apk') {
        downloads += 1;
      }
      return http.Response(
        jsonEncode({
          'versionName': '5.1.0',
          'versionCode': 40200,
          'downloadPath': '/worker-app/release/apk',
          'sha256': 'ab' * 32,
          'sizeBytes': 4,
          'mandatory': true,
        }),
        200,
      );
    });
    final platform = NoopWorkerRuntimeChannel(
      installedAppVersion: installed,
      playUpdate: const PlayAppUpdateOffer(
        available: true,
        versionCode: 40105,
        immediateAllowed: true,
      ),
    );
    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8081')),
      httpClient: client,
      platform: platform,
      encryptedStore: InMemoryEncryptedStore(),
    );
    addTearDown(controller.dispose);

    await controller.refreshAppUpdate();
    expect(controller.appUpdateFromPlay, isTrue);
    expect(controller.blocksAppUntilUpdate, isTrue);
    expect(controller.appUpdateNotes, 'Google Play will install build 40105.');

    await controller.installOfferedAppUpdate();
    expect(platform.playUpdateStarts, 1);
    expect(platform.installedApkPath, isNull);
    expect(downloads, 0);
    expect(
      controller.appUpdateNotice,
      'Confirm the Google Play screen to finish the update.',
    );
  });

  test('an unknown Play check does not invent an update', () {
    expect(
      PlayAppUpdateOffer.fromMap(const {'known': false, 'available': true}),
      isNull,
    );
    expect(
      PlayAppUpdateOffer.fromMap(const {'available': false})?.available,
      isFalse,
    );
  });
}

class _InstallGateChannel extends NoopWorkerRuntimeChannel {
  _InstallGateChannel({required super.storePath})
    : super(
        installedAppVersion: const InstalledAppVersion(
          versionName: '5.0.0',
          versionCode: 40100,
        ),
      );

  InstalledAppVersion installed = const InstalledAppVersion(
    versionName: '5.0.0',
    versionCode: 40100,
  );
  var failInstall = false;

  @override
  Future<InstalledAppVersion?> readInstalledAppVersion() async => installed;

  @override
  Future<WorkerAppInstallPrompt> installDownloadedApk(String path) async {
    installedApkPath = path;
    if (failInstall) {
      throw PlatformException(
        code: 'INSTALL_UNAVAILABLE',
        message: 'No package installer is available',
      );
    }
    return WorkerAppInstallPrompt.installerLaunched;
  }
}
