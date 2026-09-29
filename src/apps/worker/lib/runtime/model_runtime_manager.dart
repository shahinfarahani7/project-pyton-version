import 'inference_adapter.dart';
import 'artifact_install_coordinator.dart';
import 'model_artifact_verifier.dart';
import 'runtime_exclusive_group_enforcer.dart';

enum ModelResidencyState { unloaded, resident, unloading }

enum ModelUnloadReason {
  memoryPressure,
  lifecycleShutdown,
  modelReplacement,
  corruption,
  idlePolicy,
}

/// Tracks one resident primary heavy model and short-lived inference sessions.
///
/// Architecture Section 24: model lifetime != session lifetime.
abstract class ModelRuntimeManager {
  bool get allowsOnlyOnePrimaryHeavyModel => true;

  ModelResidencyState get residencyState;

  String? get residentModelVersionId;

  int get openSessionCount;

  Future<void> ensureResident({
    required ModelArtifact artifact,
    required String signingKey,
  });

  Future<void> unload({
    required ModelUnloadReason reason,
    bool force = false,
  });

  Future<T> withFreshSession<T>({
    required String stageId,
    required Future<T> Function() body,
    String? sessionOwner,
  });
}

/// Test double that records load/unload/session boundaries without native runtime.
class InMemoryModelRuntimeManager implements ModelRuntimeManager {
  InMemoryModelRuntimeManager({
    this.verifyArtifact = true,
    RuntimeExclusiveGroupEnforcer? exclusiveGroupEnforcer,
    ModelArtifactVerifier? artifactVerifier,
  })  : _exclusiveGroupEnforcer = exclusiveGroupEnforcer,
        _artifactVerifier = artifactVerifier ?? const ModelArtifactVerifier();

  final bool verifyArtifact;
  final RuntimeExclusiveGroupEnforcer? _exclusiveGroupEnforcer;
  final ModelArtifactVerifier _artifactVerifier;
  @override
  bool get allowsOnlyOnePrimaryHeavyModel => true;

  ModelResidencyState _state = ModelResidencyState.unloaded;
  String? _modelVersionId;
  int _openSessions = 0;
  int loadCount = 0;
  int unloadCount = 0;
  int sessionCount = 0;
  final List<String> sessionStages = [];
  final List<ModelUnloadReason> unloadReasons = [];

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
    if (verifyArtifact) {
      _artifactVerifier.verifyOrThrow(artifact: artifact, signingKey: signingKey);
    }
    if (_state == ModelResidencyState.resident &&
        _modelVersionId != null &&
        _modelVersionId != artifact.modelVersionId) {
      ArtifactInstallCoordinator.instance.assertUpgradeAllowedDuringSession(
        openSessionCount: _openSessions,
      );
      await unload(reason: ModelUnloadReason.modelReplacement, force: true);
    }
    if (_state != ModelResidencyState.resident) {
      loadCount += 1;
      _modelVersionId = artifact.modelVersionId;
      _state = ModelResidencyState.resident;
    }
  }

  @override
  Future<void> unload({
    required ModelUnloadReason reason,
    bool force = false,
  }) async {
    if (!force && _openSessions > 0) {
      throw StateError('Cannot unload while sessions are open');
    }
    if (_state == ModelResidencyState.unloaded) {
      return;
    }
    _state = ModelResidencyState.unloading;
    unloadCount += 1;
    unloadReasons.add(reason);
    _modelVersionId = null;
    _openSessions = 0;
    _state = ModelResidencyState.unloaded;
  }

  @override
  Future<T> withFreshSession<T>({
    required String stageId,
    required Future<T> Function() body,
    String? sessionOwner,
  }) async {
    if (_state != ModelResidencyState.resident) {
      throw StateError('Model not resident');
    }
    _openSessions += 1;
    sessionCount += 1;
    sessionStages.add(stageId);
    Future<T> runBody() async {
      try {
        return await body();
      } finally {
        _openSessions -= 1;
      }
    }

    final enforcer = _exclusiveGroupEnforcer;
    if (enforcer == null) {
      return runBody();
    }
    return enforcer.withHeavyLlmInference(runBody);
  }
}
