import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/core/di/service_registry.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../models/worker_model_catalog.dart';
import 'gemma_bootstrap.dart';

/// Installs or restores the on-device Qwen3 model without redundant downloads.
abstract final class WorkerModelInstaller {
  static const _runtimeChannel = MethodChannel('io.edgemint/worker_runtime');
  /// Older builds saved the backend proxy download as `artifact` instead of the
  /// real filename — treat as a legacy install id.
  static const legacyMisnamedId = 'artifact';

  static const externalSideloadPaths = [
    '/sdcard/Edgemint/models/${WorkerModelCatalog.fileName}',
    '/storage/emulated/0/Edgemint/models/${WorkerModelCatalog.fileName}',
    '/sdcard/Download/${WorkerModelCatalog.fileName}',
    '/storage/emulated/0/Download/${WorkerModelCatalog.fileName}',
  ];

  static Future<bool> ensureReady({void Function(String message)? log}) async {
    await GemmaBootstrap.ensureInitialized();

    final sideloadPath = await _findExternalSideload();

    final importedPath = await _importViaPlatform(log: log);
    if (importedPath != null) {
      if (await _installFromExternalFile(importedPath, log: log)) {
        return true;
      }
    }

    if (FlutterGemma.hasActiveModel()) {
      try {
        await FlutterGemma.getActiveModel(
          maxTokens: 4096,
          preferredBackend: PreferredBackend.cpu,
        );
        log?.call('Qwen3 model already active');
        return true;
      } catch (error) {
        log?.call('Active model restore failed: $error');
        await _clearStaleRegistration(log: log);
      }
    }

    // Prefer adb sideload when present — metadata in app storage may be stale.
    if (sideloadPath != null) {
      log?.call('External model found — importing from $sideloadPath');
      if (await _installFromExternalFile(sideloadPath, log: log)) {
        return true;
      }
    }

    if (await FlutterGemma.isModelInstalled(WorkerModelCatalog.fileName)) {
      log?.call('Qwen3 registered — activating from app storage');
      final ok = await _activateFromInstalledId(WorkerModelCatalog.fileName, log: log);
      if (ok) {
        return true;
      }
      log?.call('Stale registry entry — clearing and retrying sideload');
      await _clearStaleRegistration(
        modelId: WorkerModelCatalog.fileName,
        log: log,
      );
      if (sideloadPath != null) {
        return _installFromExternalFile(sideloadPath, log: log);
      }
    }

    if (await FlutterGemma.isModelInstalled(legacyMisnamedId)) {
      log?.call('Migrating legacy model file name ($legacyMisnamedId)');
      return _migrateLegacyArtifact(log: log);
    }

    final installed = await FlutterGemma.listInstalledModels();
    for (final modelId in installed) {
      if (modelId == WorkerModelCatalog.fileName ||
          modelId == legacyMisnamedId ||
          modelId.toLowerCase().contains('qwen') ||
          modelId.endsWith('.litertlm')) {
        log?.call('Trying to activate installed model: $modelId');
        if (await _activateFromInstalledId(modelId, log: log)) {
          return true;
        }
      }
    }
    if (installed.isNotEmpty) {
      log?.call('Installed models: ${installed.join(", ")}');
    }
    return false;
  }

  static Future<bool> verifyActive({void Function(String message)? log}) async {
    await GemmaBootstrap.ensureInitialized();
    if (!FlutterGemma.hasActiveModel()) {
      return false;
    }
    try {
      await FlutterGemma.getActiveModel(
        maxTokens: 4096,
        preferredBackend: PreferredBackend.cpu,
      );
      log?.call('Qwen3 model verified active');
      return true;
    } catch (error) {
      log?.call('Model activation check failed: $error');
      return false;
    }
  }

  static Future<void> _clearStaleRegistration({
    String? modelId,
    void Function(String message)? log,
  }) async {
    try {
      await FlutterGemma.clearActiveInferenceIdentity();
    } catch (_) {}
    if (modelId != null) {
      try {
        await FlutterGemma.uninstallModel(modelId);
      } catch (_) {}
    }
    log?.call('Cleared stale on-device model registry');
  }

  static Future<String?> _importViaPlatform({void Function(String message)? log}) async {
    if (kIsWeb || !Platform.isAndroid) {
      return null;
    }
    try {
      log?.call('Checking sideload paths via Android import…');
      final raw = await _runtimeChannel.invokeMethod<Map<Object?, Object?>>(
        'importSideloadedModel',
        {'fileName': WorkerModelCatalog.fileName},
      );
      final path = raw?['path'] as String?;
      if (path == null || path.isEmpty) {
        log?.call('No sideload model found on device storage');
        return null;
      }
      final copiedFrom = raw?['copiedFrom'] as String?;
      if (copiedFrom != null) {
        log?.call('Imported sideload model from $copiedFrom');
      } else {
        log?.call('Using model already in app storage: $path');
      }
      return path;
    } catch (error) {
      log?.call('Native sideload import failed: $error');
      return null;
    }
  }

  static Future<String?> _findExternalSideload() async {
    if (kIsWeb || !Platform.isAndroid) {
      return null;
    }
    for (final candidate in externalSideloadPaths) {
      if (await File(candidate).exists()) {
        return candidate;
      }
    }
    return null;
  }

  static Future<bool> _activateFromInstalledId(
    String modelId, {
    void Function(String message)? log,
  }) async {
    final path = await _installedModelPath(modelId);
    if (path == null) {
      log?.call('Model $modelId metadata missing on disk');
      return false;
    }
    return _installFromExternalFile(path, log: log);
  }

  static Future<bool> _migrateLegacyArtifact({void Function(String message)? log}) async {
    final legacyPath = await _installedModelPath(legacyMisnamedId);
    if (legacyPath == null) {
      return false;
    }
    final ok = await _installFromExternalFile(legacyPath, log: log);
    if (ok) {
      try {
        await FlutterGemma.uninstallModel(legacyMisnamedId);
      } catch (_) {}
    }
    return ok;
  }

  static Future<String?> _installedModelPath(String modelId) async {
    try {
      final path =
          await ServiceRegistry.instance.fileSystemService.getTargetPath(modelId);
      if (await File(path).exists()) {
        return path;
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> _installFromExternalFile(
    String path, {
    void Function(String message)? log,
  }) async {
    try {
      await WorkerModelCatalog.installBuilder()
          .fromFile(path)
          .install();
      await FlutterGemma.getActiveModel(
        maxTokens: 4096,
        preferredBackend: PreferredBackend.cpu,
      );
      log?.call('Qwen3 model ready (local file, no download)');
      return true;
    } catch (error) {
      log?.call('Local model activation failed: $error');
      return false;
    }
  }

  static Future<void> installFromNetwork({
    required String downloadUrl,
    required void Function(int progress) onProgress,
    void Function(String message)? log,
  }) async {
    await GemmaBootstrap.ensureInitialized();
    log?.call('Starting network install: $downloadUrl');
    await WorkerModelCatalog.installBuilder()
        .fromNetwork(downloadUrl, foreground: true)
        .withProgress(onProgress)
        .install();
    await FlutterGemma.getActiveModel(
      maxTokens: 4096,
      preferredBackend: PreferredBackend.cpu,
    );
    log?.call('Qwen3 model ready');
  }
}
