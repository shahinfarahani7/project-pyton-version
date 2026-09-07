import 'dart:developer' as developer;

/// Causal trace for active-model identity and Native handle lifecycle (v2 §76).
class IdentityLifecycleTracer {
  IdentityLifecycleTracer._();

  static final IdentityLifecycleTracer instance = IdentityLifecycleTracer._();

  static const _maxRecentEvents = 8;

  int _eventSequence = 0;
  int _bootstrapDepth = 0;
  int _nativeModelCreateCount = 0;
  int _nativeModelCloseCount = 0;
  int _nativeSessionCreateCount = 0;
  int _nativeSessionCloseCount = 0;
  int _identityClearCount = 0;
  DateTime? _lastIdentityClearAt;
  final List<Map<String, dynamic>> _recentEvents = [];

  bool get bootstrapInFlight => _bootstrapDepth > 0;

  int get nativeModelCreateCount => _nativeModelCreateCount;

  int get nativeModelCloseCount => _nativeModelCloseCount;

  int get nativeSessionCreateCount => _nativeSessionCreateCount;

  int get nativeSessionCloseCount => _nativeSessionCloseCount;

  int get identityClearCount => _identityClearCount;

  /// Serialize overlapping bootstrap paths (ensureModelReady + verifyActive).
  Future<T> guardBootstrap<T>({
    required String caller,
    required Future<T> Function() body,
  }) async {
    recordMutation(
      kind: 'bootstrapStarted',
      caller: caller,
      afterState: {'bootstrapInFlight': true},
    );
    _bootstrapDepth += 1;
    try {
      return await body();
    } finally {
      _bootstrapDepth -= 1;
      recordMutation(
        kind: 'bootstrapCompleted',
        caller: caller,
        afterState: {'bootstrapInFlight': bootstrapInFlight},
      );
    }
  }

  void recordMutation({
    required String kind,
    required String caller,
    Map<String, dynamic>? beforeState,
    Map<String, dynamic>? afterState,
    String? reason,
  }) {
    _eventSequence += 1;
    final event = <String, dynamic>{
      'sequence': _eventSequence,
      'kind': kind,
      'caller': caller,
      if (reason != null) 'reason': reason,
      if (beforeState != null) 'before': beforeState,
      if (afterState != null) 'after': afterState,
      'observedAt': DateTime.now().toUtc().toIso8601String(),
    };
    _recentEvents.add(event);
    if (_recentEvents.length > _maxRecentEvents) {
      _recentEvents.removeAt(0);
    }
    developer.log(
      '[IdentityLifecycle] $kind caller=$caller reason=${reason ?? "-"}',
      name: 'EdgeMintIdentity',
    );
  }

  void recordNativeModelCreate({required String caller}) {
    _nativeModelCreateCount += 1;
    recordMutation(
      kind: 'modelLoad',
      caller: caller,
      afterState: {'nativeModelCreateCount': _nativeModelCreateCount},
    );
  }

  void recordNativeModelClose({required String caller, String? reason}) {
    _nativeModelCloseCount += 1;
    recordMutation(
      kind: 'modelUnload',
      caller: caller,
      reason: reason,
      afterState: {'nativeModelCloseCount': _nativeModelCloseCount},
    );
  }

  void recordNativeSessionOpen({required String caller, required String stageId}) {
    _nativeSessionCreateCount += 1;
    recordMutation(
      kind: 'sessionOpen',
      caller: caller,
      afterState: {
        'stageId': stageId,
        'nativeSessionCreateCount': _nativeSessionCreateCount,
      },
    );
  }

  void recordNativeSessionClose({required String caller, required String stageId}) {
    _nativeSessionCloseCount += 1;
    recordMutation(
      kind: 'sessionClose',
      caller: caller,
      afterState: {
        'stageId': stageId,
        'nativeSessionCloseCount': _nativeSessionCloseCount,
      },
    );
  }

  void recordIdentityClear({required String caller, required String reason}) {
    _identityClearCount += 1;
    _lastIdentityClearAt = DateTime.now().toUtc();
    recordMutation(
      kind: 'clearActiveInferenceIdentity',
      caller: caller,
      reason: reason,
      afterState: {'identityClearCount': _identityClearCount},
    );
  }

  void recordNativeHandlesInvalidated({required String reason}) {
    recordMutation(
      kind: 'nativeHandlesInvalidated',
      caller: 'ProcessLifecycleCoordinator',
      reason: reason,
      afterState: {'nativeHandlesInvalidated': true},
    );
  }

  bool detectIdleChurn({required bool hasActiveAssignment}) {
    if (hasActiveAssignment) {
      return false;
    }
    if (_identityClearCount == 0) {
      return false;
    }
    if (_lastIdentityClearAt == null) {
      return false;
    }
    final minutesSinceClear = DateTime.now().toUtc().difference(_lastIdentityClearAt!).inMinutes;
    return minutesSinceClear < 60 && _identityClearCount >= 2;
  }

  Map<String, dynamic> heartbeatView({
    required int runtimeGeneration,
    required bool nativeHandlesInvalidated,
    required bool hasActiveAssignment,
  }) {
    return {
      'eventSequence': _eventSequence,
      'bootstrapInFlight': bootstrapInFlight,
      'runtimeGeneration': runtimeGeneration,
      'nativeHandlesInvalidated': nativeHandlesInvalidated,
      'idleChurnDetected': detectIdleChurn(hasActiveAssignment: hasActiveAssignment),
      'nativeHandleCounters': {
        'modelCreate': _nativeModelCreateCount,
        'modelClose': _nativeModelCloseCount,
        'sessionCreate': _nativeSessionCreateCount,
        'sessionClose': _nativeSessionCloseCount,
        'identityClear': _identityClearCount,
      },
      'recentMutations': List<Map<String, dynamic>>.from(_recentEvents),
    };
  }

  void resetForTests() {
    _eventSequence = 0;
    _bootstrapDepth = 0;
    _nativeModelCreateCount = 0;
    _nativeModelCloseCount = 0;
    _nativeSessionCreateCount = 0;
    _nativeSessionCloseCount = 0;
    _identityClearCount = 0;
    _lastIdentityClearAt = null;
    _recentEvents.clear();
  }
}
