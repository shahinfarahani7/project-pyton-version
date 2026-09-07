import 'dart:developer' as developer;

import 'package:flutter_gemma/flutter_gemma.dart';

import '../models/worker_model_catalog.dart';
import 'artifact_install_coordinator.dart';
import 'inference_adapter.dart';
import 'identity_lifecycle_tracer.dart';
import 'model_artifact_verifier.dart';
import 'model_runtime_manager.dart';
import 'runtime_exceptions.dart';
import 'runtime_exclusive_group_enforcer.dart';

/// Gemma/Qwen LiteRT implementation of [ModelRuntimeManager].
class GemmaModelRuntimeManager implements ModelRuntimeManager {
  GemmaModelRuntimeManager({
    RuntimeExclusiveGroupEnforcer? exclusiveGroupEnforcer,
    ModelArtifactVerifier? artifactVerifier,
  })  : _exclusiveGroupEnforcer = exclusiveGroupEnforcer,
        _artifactVerifier = artifactVerifier ?? const ModelArtifactVerifier();

  final RuntimeExclusiveGroupEnforcer? _exclusiveGroupEnforcer;
  final ModelArtifactVerifier _artifactVerifier;
  InferenceModel? _model;
  ModelResidencyState _state = ModelResidencyState.unloaded;
  String? _modelVersionId;
  int _openSessions = 0;

  static const _maxTokens = 1280;

  void _log(String message) {
    developer.log(message, name: 'EdgeMintModelRuntime');
  }

  @override
  ModelResidencyState get residencyState => _state;

  @override
  String? get residentModelVersionId => _modelVersionId;

  @override
  int get openSessionCount => _openSessions;

  @override
  Future<void> ensureResident({
    required ModelArtifact artifact,
    required String signingKey,
  }) async {
    if (_state == ModelResidencyState.resident &&
        _modelVersionId == artifact.modelVersionId &&
        _model != null) {
      _log('[MODEL RESIDENT] reuse modelVersionId=${artifact.modelVersionId}');
      return;
    }

    if (_state == ModelResidencyState.resident && _modelVersionId != artifact.modelVersionId) {
      ArtifactInstallCoordinator.instance.assertUpgradeAllowedDuringSession(
        openSessionCount: _openSessions,
      );
      await unload(reason: ModelUnloadReason.modelReplacement, force: true);
    }

    if (artifact.backend != InferenceBackend.liteRt) {
      throw ModelIntegrityException('Expected LiteRT model artifact');
    }

    _artifactVerifier.verifyOrThrow(artifact: artifact, signingKey: signingKey);

    if (artifact.digestSha256 != WorkerModelCatalog.installedDigestMarker &&
        artifact.modelVersionId != WorkerModelCatalog.modelVersionId) {
      throw ModelIntegrityException('Unexpected model version for worker runtime');
    }

    _log(
      '[MODEL LOAD] profile=${WorkerModelCatalog.profileId} '
      'model=${WorkerModelCatalog.displayName}',
    );

    try {
      _model = await FlutterGemma.getActiveModel(
        maxTokens: _maxTokens,
        preferredBackend: PreferredBackend.cpu,
      );
      IdentityLifecycleTracer.instance.recordNativeModelCreate(
        caller: 'GemmaModelRuntimeManager.ensureResident',
      );
      _modelVersionId = artifact.modelVersionId;
      _state = ModelResidencyState.resident;
      _log('[MODEL LOAD] successful maxTokens=$_maxTokens');
    } catch (error, stackTrace) {
      _model = null;
      _modelVersionId = null;
      _state = ModelResidencyState.unloaded;
      developer.log(
        '[MODEL LOAD] failed: $error',
        name: 'EdgeMintModelRuntime',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<void> unload({
    required ModelUnloadReason reason,
    bool force = false,
  }) async {
    if (!force && _openSessions > 0) {
      throw StateError('Cannot unload model while $_openSessions session(s) are open');
    }

    final model = _model;
    if (model == null || _state == ModelResidencyState.unloaded) {
      _model = null;
      _modelVersionId = null;
      _state = ModelResidencyState.unloaded;
      return;
    }

    _state = ModelResidencyState.unloading;
    _model = null;
    _modelVersionId = null;

    try {
      await model.close();
      IdentityLifecycleTracer.instance.recordNativeModelClose(
        caller: 'GemmaModelRuntimeManager.unload',
        reason: reason.name,
      );
      _log('[MODEL UNLOAD] reason=${reason.name}');
    } catch (error, stackTrace) {
      developer.log(
        '[MODEL UNLOAD] failed: $error',
        name: 'EdgeMintModelRuntime',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _openSessions = 0;
      _state = ModelResidencyState.unloaded;
    }
  }

  @override
  Future<T> withFreshSession<T>({
    required String stageId,
    required Future<T> Function() body,
  }) async {
    if (_state != ModelResidencyState.resident || _model == null) {
      throw StateError('Primary model is not resident');
    }

    _openSessions += 1;
    IdentityLifecycleTracer.instance.recordNativeSessionOpen(
      caller: 'GemmaModelRuntimeManager.withFreshSession',
      stageId: stageId,
    );
    _log('[SESSION OPEN] stage=$stageId open=$_openSessions');
    Future<T> runBody() async {
      try {
        return await body();
      } finally {
        _openSessions -= 1;
        IdentityLifecycleTracer.instance.recordNativeSessionClose(
          caller: 'GemmaModelRuntimeManager.withFreshSession',
          stageId: stageId,
        );
        _log('[SESSION CLOSE] stage=$stageId open=$_openSessions');
      }
    }

    final enforcer = _exclusiveGroupEnforcer;
    if (enforcer == null) {
      return runBody();
    }
    return enforcer.withHeavyLlmInference(runBody);
  }

  InferenceModel requireModel() {
    final model = _model;
    if (_state != ModelResidencyState.resident || model == null) {
      throw StateError('Primary model is not resident');
    }
    return model;
  }
}
