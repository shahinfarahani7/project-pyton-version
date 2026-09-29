import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../contracts/worker_error.dart';
import '../models/worker_model_catalog.dart';
import '../models/worker_model_runtime_candidate.dart';
import 'artifact_install_coordinator.dart';
import 'gemma4_e4b_gpu_benchmark.dart';
import 'gemma_multimodal_vision_runtime.dart';
import 'inference_adapter.dart';
import 'identity_lifecycle_tracer.dart';
import 'model_artifact_verifier.dart';
import 'model_runtime_manager.dart';
import 'runtime_exceptions.dart';
import 'runtime_exclusive_group_enforcer.dart';
import 'worker_model_installer.dart';

typedef GemmaActiveModelLoader = Future<InferenceModel> Function({
  required int maxTokens,
  required PreferredBackend preferredBackend,
  required bool supportImage,
  required int maxNumImages,
});

/// Gemma/Qwen LiteRT implementation of [ModelRuntimeManager].
class GemmaModelRuntimeManager implements ModelRuntimeManager {
  GemmaModelRuntimeManager({
    RuntimeExclusiveGroupEnforcer? exclusiveGroupEnforcer,
    ModelArtifactVerifier? artifactVerifier,
    PreferredBackend preferredBackend = PreferredBackend.gpu,
    GemmaActiveModelLoader? activeModelLoader,
  })  : _exclusiveGroupEnforcer = exclusiveGroupEnforcer,
        _artifactVerifier = artifactVerifier ?? const ModelArtifactVerifier(),
        _preferredBackend = preferredBackend,
        _activeModelLoader = activeModelLoader ?? _defaultActiveModelLoader;

  final RuntimeExclusiveGroupEnforcer? _exclusiveGroupEnforcer;
  final ModelArtifactVerifier _artifactVerifier;
  PreferredBackend _preferredBackend;
  final GemmaActiveModelLoader _activeModelLoader;

  @override
  bool get allowsOnlyOnePrimaryHeavyModel => true;
  InferenceModel? _model;
  ModelResidencyState _state = ModelResidencyState.unloaded;
  String? _modelVersionId;
  int _openSessions = 0;
  bool _visionExecutorLoaded = false;
  ModelArtifact? _lastArtifact;
  String? _lastSigningKey;

  int get _residentMaxTokens => Gemma4E4bBenchmarkMode.residentMaxTokens;

  @visibleForTesting
  bool get visionExecutorLoaded => _visionExecutorLoaded;

  @visibleForTesting
  int get configuredMaxNumImages => _visionExecutorLoaded
      ? GemmaLitertMultimodalVisionPolicy.multimodalMaxNumImages
      : GemmaLitertMultimodalVisionPolicy.textOnlyMaxNumImages;

  @visibleForTesting
  String? lastRequestedCapability;

  @visibleForTesting
  String? lastResidentCapability;

  @visibleForTesting
  String? lastCapabilityAction;

  String get _residentCapabilityLabel {
    if (_state != ModelResidencyState.resident || _model == null) {
      return 'none';
    }
    return _visionExecutorLoaded ? 'vision' : 'text';
  }

  void _logCapabilityDecision({
    required String requestedCapability,
    required String residentCapability,
    required String action,
  }) {
    lastRequestedCapability = requestedCapability;
    lastResidentCapability = residentCapability;
    lastCapabilityAction = action;
    _log(
      '[MODEL CAPABILITY] requestedCapability=$requestedCapability '
      'residentCapability=$residentCapability action=$action',
    );
  }

  static Future<InferenceModel> _defaultActiveModelLoader({
    required int maxTokens,
    required PreferredBackend preferredBackend,
    required bool supportImage,
    required int maxNumImages,
  }) {
    return FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: preferredBackend,
      supportImage: supportImage,
      maxNumImages: supportImage ? maxNumImages : null,
    );
  }

  void _log(String message) {
    developer.log(message, name: 'EdgeMintModelRuntime');
  }

  @override
  ModelResidencyState get residencyState => _state;

  @override
  String? get residentModelVersionId => _modelVersionId;

  @override
  int get openSessionCount => _openSessions;

  PreferredBackend get preferredBackend => _preferredBackend;

  void configurePreferredBackend(PreferredBackend backend) {
    _preferredBackend = backend;
  }

  @override
  Future<void> ensureResident({
    required ModelArtifact artifact,
    required String signingKey,
  }) {
    return ensureResidentForAssignment(
      artifact: artifact,
      signingKey: signingKey,
      enableVision: false,
    );
  }

  /// Loads or reuses the resident engine for the current assignment.
  ///
  /// When [enableVision] is true and nothing is resident, the first native
  /// load is multimodal. A text-only resident engine is upgraded once.
  /// A vision-capable resident engine is never downgraded.
  Future<void> ensureResidentForAssignment({
    required ModelArtifact artifact,
    required String signingKey,
    required bool enableVision,
  }) async {
    _lastArtifact = artifact;
    _lastSigningKey = signingKey;

    final requestedCapability = enableVision ? 'vision' : 'text';
    final residentCapability = _residentCapabilityLabel;
    final sameModel = _state == ModelResidencyState.resident &&
        _modelVersionId == artifact.modelVersionId &&
        _model != null;

    if (sameModel && (_visionExecutorLoaded || !enableVision)) {
      _logCapabilityDecision(
        requestedCapability: requestedCapability,
        residentCapability: residentCapability,
        action: 'reuse',
      );
      _log(
        '${GemmaLitertMultimodalVisionPolicy.visionRuntimeLogLine(visionExecutorLoaded: _visionExecutorLoaded, multimodal: enableVision)} '
        'reuse modelVersionId=${artifact.modelVersionId}',
      );
      return;
    }

    if (sameModel && enableVision && !_visionExecutorLoaded) {
      _logCapabilityDecision(
        requestedCapability: requestedCapability,
        residentCapability: residentCapability,
        action: 'upgrade',
      );
      await _upgradeResidentEngineToVision(
        artifact: artifact,
        signingKey: signingKey,
      );
      return;
    }

    if (_state == ModelResidencyState.resident && _modelVersionId != artifact.modelVersionId) {
      ArtifactInstallCoordinator.instance.assertUpgradeAllowedDuringSession(
        openSessionCount: _openSessions,
      );
      await unload(reason: ModelUnloadReason.modelReplacement, force: true);
    }

    _logCapabilityDecision(
      requestedCapability: requestedCapability,
      residentCapability: 'none',
      action: 'load',
    );
    await _loadResidentEngine(
      artifact: artifact,
      signingKey: signingKey,
      enableVision: enableVision,
    );
  }

  /// Upgrades the LiteRT engine to multimodal (`max_num_images >= 1`) before image inference.
  ///
  /// Vision is **engine-initialized** via `FlutterGemma.getActiveModel(supportImage: true)` —
  /// not lazy-loaded per chat session on the current FFI bindings.
  Future<void> ensureMultimodalVisionEngine() async {
    if (_visionExecutorLoaded && _model != null) {
      _logCapabilityDecision(
        requestedCapability: 'vision',
        residentCapability: 'vision',
        action: 'reuse',
      );
      _log(
        GemmaLitertMultimodalVisionPolicy.visionRuntimeLogLine(
          visionExecutorLoaded: true,
          multimodal: true,
        ),
      );
      return;
    }

    _log(
      '[VISION UPGRADE] activeSessions=$_openSessions '
      'visionExecutorLoaded=$_visionExecutorLoaded '
      'engineMode=${_visionExecutorLoaded ? "multimodal" : "text-only"}',
    );

    final artifact = _lastArtifact;
    final signingKey = _lastSigningKey;
    if (artifact == null || signingKey == null) {
      throw GemmaLitertMultimodalVisionPolicy.visionRuntimeNotReady(
        'Primary model must be resident before multimodal vision can load',
      );
    }

    final residentCapability = _residentCapabilityLabel;
    if (_state == ModelResidencyState.resident && _model != null) {
      _logCapabilityDecision(
        requestedCapability: 'vision',
        residentCapability: residentCapability,
        action: 'upgrade',
      );
      await _upgradeResidentEngineToVision(
        artifact: artifact,
        signingKey: signingKey,
      );
      return;
    }

    _logCapabilityDecision(
      requestedCapability: 'vision',
      residentCapability: 'none',
      action: 'load',
    );
    await _loadResidentEngine(
      artifact: artifact,
      signingKey: signingKey,
      enableVision: true,
    );
    _log(
      GemmaLitertMultimodalVisionPolicy.visionRuntimeLogLine(
        visionExecutorLoaded: true,
        multimodal: true,
      ),
    );
  }

  Future<void> _upgradeResidentEngineToVision({
    required ModelArtifact artifact,
    required String signingKey,
  }) async {
    if (_openSessions > 0) {
      throw GemmaLitertMultimodalVisionPolicy.visionRuntimeNotReady(
        'Cannot upgrade LiteRT vision executor while $_openSessions session(s) are open',
      );
    }

    if (_state == ModelResidencyState.resident && _model != null) {
      await unload(reason: ModelUnloadReason.modelReplacement, force: true);
    }

    await _loadResidentEngine(
      artifact: artifact,
      signingKey: signingKey,
      enableVision: true,
    );
    _log(
      '[VISION UPGRADE] complete engineMode=multimodal '
      'maxNumImages=${GemmaLitertMultimodalVisionPolicy.multimodalMaxNumImages}',
    );
    _log(
      GemmaLitertMultimodalVisionPolicy.visionRuntimeLogLine(
        visionExecutorLoaded: true,
        multimodal: true,
      ),
    );
  }

  Future<void> _loadResidentEngine({
    required ModelArtifact artifact,
    required String signingKey,
    required bool enableVision,
  }) async {
    if (artifact.backend != InferenceBackend.liteRt) {
      throw ModelIntegrityException('Expected LiteRT model artifact');
    }

    _artifactVerifier.verifyOrThrow(artifact: artifact, signingKey: signingKey);

    if (artifact.digestSha256 != WorkerModelCatalog.installedDigestMarker &&
        !WorkerModelRuntimeCandidateRegistry.isKnownRuntimeModelVersionId(
          artifact.modelVersionId,
        )) {
      throw ModelIntegrityException('Unexpected model version for worker runtime');
    }

    final maxNumImages = enableVision
        ? GemmaLitertMultimodalVisionPolicy.multimodalMaxNumImages
        : GemmaLitertMultimodalVisionPolicy.textOnlyMaxNumImages;

    _log(
      '[MODEL LOAD] profile=${WorkerModelCatalog.profileId} '
      'model=${WorkerModelCatalog.displayName} '
      'backend=${_preferredBackend.name}, maxTokens=$_residentMaxTokens '
      'enableVision=$enableVision maxNumImages=$maxNumImages',
    );

    await WorkerModelInstaller.prepareForNativeInference(log: _log);

    try {
      _model = await _activeModelLoader(
        maxTokens: _residentMaxTokens,
        preferredBackend: _preferredBackend,
        supportImage: enableVision,
        maxNumImages: maxNumImages,
      );
      IdentityLifecycleTracer.instance.recordNativeModelCreate(
        caller: 'GemmaModelRuntimeManager._loadResidentEngine',
      );
      _modelVersionId = artifact.modelVersionId;
      _state = ModelResidencyState.resident;
      _visionExecutorLoaded = enableVision;
      _log('[MODEL LOAD] successful maxTokens=$_residentMaxTokens');
      if (!enableVision) {
        _log(
          GemmaLitertMultimodalVisionPolicy.visionRuntimeLogLine(
            visionExecutorLoaded: false,
            multimodal: false,
          ),
        );
      }
    } catch (error, stackTrace) {
      _model = null;
      _modelVersionId = null;
      _state = ModelResidencyState.unloaded;
      _visionExecutorLoaded = false;
      developer.log(
        '[MODEL LOAD] failed: $error',
        name: 'EdgeMintModelRuntime',
        error: error,
        stackTrace: stackTrace,
      );
      final classified = GemmaLitertMultimodalVisionPolicy.classifyInferenceFailure(
        error,
      );
      if (classified != null) {
        throw classified;
      }
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
      _visionExecutorLoaded = false;
      return;
    }

    _state = ModelResidencyState.unloading;
    _model = null;
    _modelVersionId = null;
    _visionExecutorLoaded = false;

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
    String? sessionOwner,
  }) async {
    if (_state != ModelResidencyState.resident || _model == null) {
      throw StateError('Primary model is not resident');
    }

    final owner = sessionOwner ?? stageId;
    _log(
      '[SESSION ACQUIRE] owner=$owner stage=$stageId '
      'activeSessions=$_openSessions engineMode=${_visionExecutorLoaded ? "multimodal" : "text-only"}',
    );
    _openSessions += 1;
    IdentityLifecycleTracer.instance.recordNativeSessionOpen(
      caller: 'GemmaModelRuntimeManager.withFreshSession',
      stageId: stageId,
    );
    _log('[SESSION OPEN] stage=$stageId open=$_openSessions owner=$owner');
    Future<T> runBody() async {
      try {
        return await body();
      } finally {
        _openSessions -= 1;
        IdentityLifecycleTracer.instance.recordNativeSessionClose(
          caller: 'GemmaModelRuntimeManager.withFreshSession',
          stageId: stageId,
        );
        _log(
          '[SESSION RELEASE] owner=$owner stage=$stageId '
          'activeSessions=$_openSessions',
        );
        _log('[SESSION CLOSE] stage=$stageId open=$_openSessions owner=$owner');
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
