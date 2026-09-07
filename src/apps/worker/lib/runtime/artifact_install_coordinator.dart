import 'runtime_exceptions.dart';

enum ArtifactInstallPhase {
  idle,
  installing,
  verifying,
  activating,
}

/// Serializes install/verify/activate and tracks model generation (v2 §53, §54, A16).
class ArtifactInstallCoordinator {
  ArtifactInstallCoordinator._();

  static final ArtifactInstallCoordinator instance = ArtifactInstallCoordinator._();

  ArtifactInstallPhase _phase = ArtifactInstallPhase.idle;
  int _generation = 0;
  String? _activeModelVersionId;
  Future<void>? _inFlight;

  ArtifactInstallPhase get phase => _phase;

  int get generation => _generation;

  String? get activeModelVersionId => _activeModelVersionId;

  bool get installInProgress => _inFlight != null;

  void assertNoConcurrentInstall() {
    if (_inFlight != null) {
      throw ModelIntegrityException('Concurrent model install blocked');
    }
  }

  void assertUpgradeAllowedDuringSession({required int openSessionCount}) {
    if (openSessionCount > 0) {
      throw ModelIntegrityException(
        'Model upgrade blocked while inference sessions are open',
      );
    }
  }

  Future<T> runExclusiveInstall<T>({
    required String modelVersionId,
    required Future<T> Function(int installGeneration) operation,
  }) async {
    assertNoConcurrentInstall();
    final installGeneration = ++_generation;
    _phase = ArtifactInstallPhase.installing;
    final tracked = operation(installGeneration);
    _inFlight = tracked.then((_) {});
    try {
      final result = await tracked;
      _activeModelVersionId = modelVersionId;
      return result;
    } finally {
      _inFlight = null;
      _phase = ArtifactInstallPhase.idle;
    }
  }

  void markVerifying() {
    _phase = ArtifactInstallPhase.verifying;
  }

  void markActivating() {
    _phase = ArtifactInstallPhase.activating;
  }

  /// Test helper.
  void resetForTest() {
    _phase = ArtifactInstallPhase.idle;
    _generation = 0;
    _activeModelVersionId = null;
    _inFlight = null;
  }
}
