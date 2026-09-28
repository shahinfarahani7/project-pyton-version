import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/core/di/service_registry.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../models/worker_model_catalog.dart';
import 'artifact_install_coordinator.dart';
import 'gemma_bootstrap.dart';
import 'identity_lifecycle_tracer.dart';
import 'model_download_verify_hook.dart';
import 'worker_model_format_gate.dart';
import 'runtime_exceptions.dart';

/// Installs, restores, and registers the EdgeMint on-device model.
///
/// IMPORTANT:
///
/// This class manages:
/// - model file existence
/// - model installation
/// - model registration
/// - active model identity
///
/// This class MUST NOT:
/// - create an inference model instance
/// - call FlutterGemma.getActiveModel()
/// - close an inference model instance
///
/// Runtime model ownership belongs to GemmaLiteRtInferenceAdapter.
abstract final class WorkerModelInstaller {
  static const _runtimeChannel = MethodChannel('io.edgemint/worker_runtime');

  static const legacyMisnamedId = 'artifact';

  static const externalSideloadPaths = [
    '/sdcard/Edgemint/models/${WorkerModelCatalog.fileName}',
    '/storage/emulated/0/Edgemint/models/${WorkerModelCatalog.fileName}',
    '/sdcard/Download/${WorkerModelCatalog.fileName}',
    '/storage/emulated/0/Download/${WorkerModelCatalog.fileName}',
    '/sdcard/Edgemint/models/${WorkerModelCatalog.gpuFileName}',
    '/storage/emulated/0/Edgemint/models/${WorkerModelCatalog.gpuFileName}',
    '/sdcard/Download/${WorkerModelCatalog.gpuFileName}',
    '/storage/emulated/0/Download/${WorkerModelCatalog.gpuFileName}',
  ];

  static List<String> externalSideloadPathsFor(String fileName) => [
        '/sdcard/Edgemint/models/$fileName',
        '/storage/emulated/0/Edgemint/models/$fileName',
        '/sdcard/Download/$fileName',
        '/storage/emulated/0/Download/$fileName',
      ];

  /// Installs a validated `.litertlm` bundled asset when configured.
  static Future<bool> installBundledAsset({
    void Function(String message)? log,
  }) async {
    final assetPath = WorkerModelCatalog.bundledAssetFromEnvironment();
    if (assetPath == null) {
      return false;
    }

    final validation = await WorkerModelFormatGate.validateBundledAssetPath(
      assetPath,
    );
    if (!validation.accepted) {
      log?.call(
        '${validation.reasonCode}: ${validation.detail}',
      );
      return false;
    }

    await GemmaBootstrap.ensureInitialized();

    try {
      await WorkerModelCatalog.installBuilder().fromAsset(assetPath).install();
    } catch (error) {
      log?.call('Bundled model registration failed: $error');
      return false;
    }

    final path = await _installedModelPath(WorkerModelCatalog.fileName);
    if (path == null) {
      return false;
    }
    return _activateExistingFile(path, log: log);
  }

  // ---------------------------------------------------------------------------
  // Ensure ready
  // ---------------------------------------------------------------------------

  static Future<bool> ensureReady({void Function(String message)? log}) async {
    await GemmaBootstrap.ensureInitialized();

    IdentityLifecycleTracer.instance.recordMutation(
      kind: 'ensureReady',
      caller: 'WorkerModelInstaller.ensureReady',
      beforeState: {'hasActiveModel': FlutterGemma.hasActiveModel()},
    );

    log?.call('Checking ${WorkerModelCatalog.displayName} installation');

    // -------------------------------------------------------------------------
    // 1. Check canonical installed model
    // -------------------------------------------------------------------------

    final registered = await FlutterGemma.isModelInstalled(
      WorkerModelCatalog.fileName,
    );

    if (registered) {
      log?.call('${WorkerModelCatalog.displayName} is registered on device');

      final path = await _installedModelPath(WorkerModelCatalog.fileName);

      if (path != null) {
        log?.call('Installed model file exists: $path');

        // If an active identity already exists, do NOT instantiate
        // the model here. The inference adapter will do that.
        if (FlutterGemma.hasActiveModel()) {
          log?.call(
            '${WorkerModelCatalog.displayName} '
            'has an active inference identity',
          );

          return true;
        }

        // File exists but no active identity.
        // Re-register the same physical file.
        log?.call(
          'Model file exists but active identity is missing; '
          'restoring registration',
        );

        final activated = await _activateExistingFile(path, log: log);

        if (activated) {
          return true;
        }

        // IMPORTANT:
        // Never delete the physical model merely because activation failed.
        log?.call(
          'Model file is present but registration activation failed. '
          'Keeping model on disk.',
        );

        return false;
      }

      // Registered metadata exists but physical file is gone.
      log?.call('Model registry exists but physical file is missing');

      await _removeMissingFileRegistration(
        WorkerModelCatalog.fileName,
        log: log,
      );
    }

    // -------------------------------------------------------------------------
    // 2. Android-managed sideload import
    // -------------------------------------------------------------------------

    final importedPath = await _importViaPlatform(log: log);

    if (importedPath != null) {
      final installed = await _installFromExternalFile(importedPath, log: log);

      if (installed) {
        return true;
      }
    }

    // -------------------------------------------------------------------------
    // 3. Explicit external sideload locations
    // -------------------------------------------------------------------------

    final sideloadPath = await _findExternalSideload();

    if (sideloadPath != null) {
      log?.call('External model found: $sideloadPath');

      final installed = await _installFromExternalFile(sideloadPath, log: log);

      if (installed) {
        return true;
      }
    }

    // -------------------------------------------------------------------------
    // 4. Legacy registration migration
    // -------------------------------------------------------------------------

    if (await FlutterGemma.isModelInstalled(legacyMisnamedId)) {
      log?.call('Legacy model registration found: $legacyMisnamedId');

      final migrated = await _migrateLegacyArtifact(log: log);

      if (migrated) {
        return true;
      }
    }

    // -------------------------------------------------------------------------
    // 5. Diagnostics only
    // -------------------------------------------------------------------------

    final installedModels = await FlutterGemma.listInstalledModels();

    if (installedModels.isNotEmpty) {
      log?.call(
        'Installed model registry: '
        '${installedModels.join(", ")}',
      );
    } else {
      log?.call('No installed inference model found');
    }

    return false;
  }

  // ---------------------------------------------------------------------------
  // Verify active identity
  // ---------------------------------------------------------------------------

  static Future<bool> verifyActive({void Function(String message)? log}) async {
    await GemmaBootstrap.ensureInitialized();

    IdentityLifecycleTracer.instance.recordMutation(
      kind: 'verifyActive',
      caller: 'WorkerModelInstaller.verifyActive',
      beforeState: {'hasActiveModel': FlutterGemma.hasActiveModel()},
    );

    final registered = await FlutterGemma.isModelInstalled(
      WorkerModelCatalog.fileName,
    );

    if (!registered) {
      log?.call(
        '${WorkerModelCatalog.displayName} '
        'is not registered',
      );

      return false;
    }

    final path = await _installedModelPath(WorkerModelCatalog.fileName);

    if (path == null) {
      log?.call(
        '${WorkerModelCatalog.displayName} '
        'registration exists but model file is missing',
      );

      return false;
    }

    if (!FlutterGemma.hasActiveModel()) {
      log?.call('No active inference model identity');

      return false;
    }

    // IMPORTANT:
    // Do NOT call getActiveModel() here.
    //
    // Runtime loading is intentionally delegated to
    // GemmaLiteRtInferenceAdapter.
    log?.call(
      '${WorkerModelCatalog.displayName} '
      'registration and active identity verified',
    );

    return true;
  }

  // ---------------------------------------------------------------------------
  // Resolve installed model path
  // ---------------------------------------------------------------------------

  static Future<String?> installedModelPathForVerification() =>
      _installedModelPath(WorkerModelCatalog.fileName);

  static Future<String?> _installedModelPath(String modelId) async {
    try {
      final path = await ServiceRegistry.instance.fileSystemService
          .getReadTargetPath(modelId);

      final file = File(path);

      if (await file.exists()) {
        return path;
      }
    } catch (_) {
      // Missing/unreadable registration is handled by caller.
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Activate an already-existing file
  // ---------------------------------------------------------------------------

  static Future<bool> _activateExistingFile(
    String path, {
    void Function(String message)? log,
  }) async {
    final file = File(path);

    if (!await file.exists()) {
      log?.call('Cannot activate missing model file: $path');

      return false;
    }

    final size = await file.length();

    final format = await WorkerModelFormatGate.validateFileOnDisk(
      expected: WorkerModelCatalog.activeRuntimeDescriptor,
      filePath: path,
    );
    if (!format.accepted) {
      log?.call('${format.reasonCode}: ${format.detail}');
      throw ModelFormatUnsupportedException(
        format.reasonCode,
        format.detail,
      );
    }

    log?.call(
      'Activating ${WorkerModelCatalog.displayName} '
      'from existing file '
      '(${(size / 1024 / 1024).toStringAsFixed(1)} MB)',
    );

    try {
      await WorkerModelCatalog.installBuilder().fromFile(path).install();

      if (!FlutterGemma.hasActiveModel()) {
        log?.call(
          '${WorkerModelCatalog.displayName} was registered '
          'but active identity was not created',
        );

        return false;
      }

      log?.call(
        '${WorkerModelCatalog.displayName} '
        'registration activation successful',
      );

      return true;
    } catch (error) {
      log?.call(
        '${WorkerModelCatalog.displayName} '
        'registration activation failed: $error',
      );

      // IMPORTANT:
      // Never uninstall here.
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Remove stale metadata only when physical file is missing
  // ---------------------------------------------------------------------------

  static Future<void> _removeMissingFileRegistration(
    String modelId, {
    void Function(String message)? log,
  }) async {
    IdentityLifecycleTracer.instance.recordIdentityClear(
      caller: 'WorkerModelInstaller._removeMissingFileRegistration',
      reason: 'physical_model_file_missing',
    );
    try {
      await FlutterGemma.clearActiveInferenceIdentity();
    } catch (_) {
      // Best-effort cleanup.
    }

    try {
      await FlutterGemma.uninstallModel(modelId);
    } catch (_) {
      // Best-effort cleanup.
    }

    log?.call(
      'Removed stale model metadata because '
      'the physical model file was missing',
    );
  }

  // ---------------------------------------------------------------------------
  // Android sideload import
  // ---------------------------------------------------------------------------

  static Future<String?> importSideloadedArtifact({
    required String fileName,
    void Function(String message)? log,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      return null;
    }
    try {
      log?.call('Checking Android sideload locations for $fileName');
      final raw = await _runtimeChannel.invokeMethod<Map<Object?, Object?>>(
        'importSideloadedModel',
        {'fileName': fileName},
      );
      final path = raw?['path'] as String?;
      if (path == null || path.isEmpty) {
        log?.call('No sideloaded $fileName found');
        return null;
      }
      return path;
    } catch (error) {
      log?.call('Native sideload import failed for $fileName: $error');
      return null;
    }
  }

  /// Benchmark-only activation for an alternate `.litertlm` artifact.
  static Future<bool> activateBenchmarkArtifactFile(
    String path, {
    void Function(String message)? log,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      return false;
    }
    final fileName = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : WorkerModelCatalog.fileName;
    final expected =
        WorkerModelCatalog.descriptorForArtifactFileName(fileName);
    final format = await WorkerModelFormatGate.validateFileOnDisk(
      expected: expected,
      filePath: path,
    );
    if (!format.accepted) {
      log?.call('${format.reasonCode}: ${format.detail}');
      return false;
    }
    try {
      await WorkerModelCatalog.installBuilder().fromFile(path).install();
      return FlutterGemma.hasActiveModel();
    } catch (error) {
      log?.call('Benchmark artifact activation failed: $error');
      return false;
    }
  }

  static Future<String?> _importViaPlatform({
    void Function(String message)? log,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      return null;
    }

    try {
      log?.call('Checking Android sideload locations');

      final raw = await _runtimeChannel.invokeMethod<Map<Object?, Object?>>(
        'importSideloadedModel',
        {'fileName': WorkerModelCatalog.fileName},
      );

      final path = raw?['path'] as String?;

      if (path == null || path.isEmpty) {
        log?.call('No sideloaded model found');

        return null;
      }

      final copiedFrom = raw?['copiedFrom'] as String?;

      if (copiedFrom != null && copiedFrom.isNotEmpty) {
        log?.call('Imported sideloaded model from $copiedFrom');
      } else {
        log?.call('Using model already available at $path');
      }

      return path;
    } catch (error) {
      log?.call('Native sideload import failed: $error');

      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Find external sideload
  // ---------------------------------------------------------------------------

  static Future<String?> _findExternalSideload() async {
    if (kIsWeb || !Platform.isAndroid) {
      return null;
    }

    for (final candidate in externalSideloadPaths) {
      final file = File(candidate);

      if (await file.exists()) {
        return candidate;
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Legacy migration
  // ---------------------------------------------------------------------------

  static Future<bool> _migrateLegacyArtifact({
    void Function(String message)? log,
  }) async {
    final legacyPath = await _installedModelPath(legacyMisnamedId);

    if (legacyPath == null) {
      log?.call('Legacy registration exists but physical file is missing');

      return false;
    }

    final ok = await _installFromExternalFile(legacyPath, log: log);

    // Only remove the legacy registration after
    // the canonical registration succeeds.
    if (ok) {
      try {
        await FlutterGemma.uninstallModel(legacyMisnamedId);
      } catch (_) {
        // Migration itself already succeeded.
      }
    }

    return ok;
  }

  // ---------------------------------------------------------------------------
  // Install from local/external file
  // ---------------------------------------------------------------------------

  static Future<bool> _installFromExternalFile(
    String path, {
    void Function(String message)? log,
  }) async {
    try {
      final file = File(path);

      if (!await file.exists()) {
        log?.call('External model file does not exist: $path');

        return false;
      }

      final size = await file.length();

      log?.call(
        'Installing ${WorkerModelCatalog.displayName} '
        'from local file: $path '
        '(${(size / 1024 / 1024).toStringAsFixed(1)} MB)',
      );

      await WorkerModelCatalog.installBuilder().fromFile(path).install();

      if (!FlutterGemma.hasActiveModel()) {
        log?.call(
          '${WorkerModelCatalog.displayName} installed '
          'but active identity is missing',
        );

        return false;
      }

      log?.call(
        '${WorkerModelCatalog.displayName} '
        'ready from local file',
      );

      return true;
    } catch (error) {
      log?.call('Local model installation/registration failed: $error');

      // IMPORTANT:
      // Keep source/downloaded file.
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Network install
  // ---------------------------------------------------------------------------

  static Future<void> installFromNetwork({
    required String downloadUrl,
    required void Function(int progress) onProgress,
    void Function(String message)? log,
    String? signingKey,
    ModelDownloadVerifyHook? verifyHook,
  }) async {
    await ArtifactInstallCoordinator.instance.runExclusiveInstall<void>(
      modelVersionId: WorkerModelCatalog.modelVersionId,
      operation: (installGeneration) async {
        await GemmaBootstrap.ensureInitialized();

        log?.call('Starting network install: $downloadUrl (generation=$installGeneration)');

        await WorkerModelCatalog.installBuilder()
            .fromNetwork(downloadUrl, foreground: true)
            .withProgress(onProgress)
            .install();

        log?.call(
          '${WorkerModelCatalog.displayName} '
          'download/install completed',
        );

        final registered = await FlutterGemma.isModelInstalled(
          WorkerModelCatalog.fileName,
        );

        if (!registered) {
          throw StateError(
            '${WorkerModelCatalog.displayName} '
            'download completed but registration is missing',
          );
        }

        if (!FlutterGemma.hasActiveModel()) {
          throw StateError(
            '${WorkerModelCatalog.displayName} '
            'download completed but active identity is missing',
          );
        }

        if (signingKey != null) {
          ArtifactInstallCoordinator.instance.markVerifying();
          final path = await _installedModelPath(WorkerModelCatalog.fileName);
          if (path != null) {
            await (verifyHook ?? const ModelDownloadVerifyHook()).verifyInstalledFileIfPinned(
              path: path,
              signingKey: signingKey,
              modelVersionId: WorkerModelCatalog.modelVersionId,
            );
            log?.call(
              '${WorkerModelCatalog.displayName} '
              'post-download digest/signature verification passed',
            );
          }
        }

        ArtifactInstallCoordinator.instance.markActivating();
        log?.call(
          '${WorkerModelCatalog.displayName} '
          'installed and active identity is ready',
        );
      },
    );
  }
}
