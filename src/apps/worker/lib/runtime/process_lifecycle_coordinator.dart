import 'package:flutter/widgets.dart';

import 'identity_lifecycle_tracer.dart';

/// Platform process lifecycle phases for Android reconciliation (v2 §24, A17/T17).
enum ProcessLifecyclePhase {
  foreground,
  background,
  suspended,
  processTerminated,
  rebootPending,
}

/// Tracks app/process lifecycle, runtime generation and native-handle invalidation.
///
/// Process death and reboot invalidate reusable native model handles even when the
/// verified artifact file remains installed. Fresh server authorization is required
/// before resuming work or reusing local checkpoints.
class ProcessLifecycleCoordinator {
  ProcessLifecycleCoordinator({
    DateTime Function()? clock,
    this.onInvalidateNativeHandles,
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Future<void> Function(String reason)? onInvalidateNativeHandles;

  ProcessLifecyclePhase _phase = ProcessLifecyclePhase.foreground;
  int _runtimeGeneration = 1;
  bool _nativeHandlesInvalidated = false;
  DateTime? _lastTransitionAt;
  String? _lastReason;

  ProcessLifecyclePhase get phase => _phase;
  int get runtimeGeneration => _runtimeGeneration;
  bool get nativeHandlesInvalidated => _nativeHandlesInvalidated;
  DateTime? get lastTransitionAt => _lastTransitionAt;
  String? get lastReason => _lastReason;

  bool get requiresFreshGrantReconciliation =>
      _nativeHandlesInvalidated ||
      _phase == ProcessLifecyclePhase.processTerminated ||
      _phase == ProcessLifecyclePhase.rebootPending;

  void handleAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _transition(
          ProcessLifecyclePhase.foreground,
          reason: 'app_lifecycle_resumed',
        );
      case AppLifecycleState.inactive:
        _transition(
          ProcessLifecyclePhase.background,
          reason: 'app_lifecycle_inactive',
        );
      case AppLifecycleState.paused:
        _transition(
          ProcessLifecyclePhase.suspended,
          reason: 'app_lifecycle_paused',
        );
      case AppLifecycleState.detached:
        _invalidateNativeHandles(reason: 'app_lifecycle_detached');
        _transition(
          ProcessLifecyclePhase.processTerminated,
          reason: 'app_lifecycle_detached',
        );
      case AppLifecycleState.hidden:
        _transition(
          ProcessLifecyclePhase.background,
          reason: 'app_lifecycle_hidden',
        );
    }
  }

  Future<void> markProcessTerminated({required String reason}) async {
    _invalidateNativeHandles(reason: reason);
    _transition(ProcessLifecyclePhase.processTerminated, reason: reason);
    final callback = onInvalidateNativeHandles;
    if (callback != null) {
      await callback(reason);
    }
  }

  void markRebootPending({String reason = 'device_reboot'}) {
    _invalidateNativeHandles(reason: reason);
    _transition(ProcessLifecyclePhase.rebootPending, reason: reason);
  }

  void acknowledgeFreshGrantReconciliation() {
    _nativeHandlesInvalidated = false;
    if (_phase == ProcessLifecyclePhase.processTerminated ||
        _phase == ProcessLifecyclePhase.rebootPending) {
      _phase = ProcessLifecyclePhase.foreground;
      _lastTransitionAt = _clock();
      _lastReason = 'fresh_grant_reconciled';
    }
  }

  Map<String, Object?> toTelemetry() => {
        'phase': _phase.name,
        'runtimeGeneration': _runtimeGeneration,
        'nativeHandlesInvalidated': _nativeHandlesInvalidated,
        'requiresFreshGrantReconciliation': requiresFreshGrantReconciliation,
        if (_lastTransitionAt != null)
          'lastTransitionAt': _lastTransitionAt!.toIso8601String(),
        if (_lastReason != null) 'lastReason': _lastReason,
      };

  void _invalidateNativeHandles({required String reason}) {
    if (!_nativeHandlesInvalidated) {
      _nativeHandlesInvalidated = true;
      _runtimeGeneration += 1;
      _lastReason = reason;
      _lastTransitionAt = _clock();
      IdentityLifecycleTracer.instance.recordNativeHandlesInvalidated(reason: reason);
    }
  }

  void _transition(ProcessLifecyclePhase next, {required String reason}) {
    _phase = next;
    _lastReason = reason;
    _lastTransitionAt = _clock();
  }
}
