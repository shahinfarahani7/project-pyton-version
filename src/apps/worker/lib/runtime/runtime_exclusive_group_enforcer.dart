import 'dart:async';

import 'device_snapshot.dart';

/// Local exclusive-group gate aligned with production-exclusive-groups-v1 (Sections 29–31).
///
/// Default v1 policy: heavy LLM blocks OCR unless the device profile certifies
/// concurrent mediapipe_llm + paddle_ocr execution.
class RuntimeExclusiveGroupEnforcer {
  RuntimeExclusiveGroupEnforcer({
    this.llmOcrConcurrentCertified = false,
    this.defaultMaxOcrSessions = 1,
    this.certifiedMaxOcrSessions = 2,
    Duration ocrAdmissionPollInterval = const Duration(milliseconds: 10),
  })  : _ocrAdmissionPollInterval = ocrAdmissionPollInterval;

  final bool llmOcrConcurrentCertified;
  final int defaultMaxOcrSessions;
  final int certifiedMaxOcrSessions;
  final Duration _ocrAdmissionPollInterval;

  int _heavyLlmSessions = 0;
  int _ocrSessions = 0;
  final List<Completer<void>> _ocrWaiters = [];

  bool get heavyLlmActive => _heavyLlmSessions > 0;

  int get activeOcrSessions => _ocrSessions;

  ThermalState _thermalState = ThermalState.nominal;

  static int adaptiveMaxOcrSessions({
    required int baseMaxOcrSessions,
    required ThermalState thermalState,
  }) {
    return switch (thermalState) {
      ThermalState.critical || ThermalState.throttled => 1,
      ThermalState.warm => baseMaxOcrSessions > 1 ? baseMaxOcrSessions - 1 : 1,
      _ => baseMaxOcrSessions,
    };
  }

  int get maxOcrSessions =>
      adaptiveMaxOcrSessions(
        baseMaxOcrSessions:
            llmOcrConcurrentCertified ? certifiedMaxOcrSessions : defaultMaxOcrSessions,
        thermalState: _thermalState,
      );

  void updateThermalState(ThermalState thermalState) {
    _thermalState = thermalState;
  }

  bool get mustBlockOcrDuringHeavy => heavyLlmActive && !llmOcrConcurrentCertified;
  Future<T> withHeavyLlmInference<T>(Future<T> Function() body) async {
    _heavyLlmSessions += 1;
    try {
      return await body();
    } finally {
      _heavyLlmSessions -= 1;
      _wakeOcrWaiters();
    }
  }

  Future<T> withOcrInference<T>(Future<T> Function() body) async {
    await _awaitOcrAdmission();
    _ocrSessions += 1;
    try {
      return await body();
    } finally {
      _ocrSessions -= 1;
      _wakeOcrWaiters();
    }
  }

  Future<void> _awaitOcrAdmission() async {
    while (_mustWaitForOcrAdmission()) {
      final waiter = Completer<void>();
      _ocrWaiters.add(waiter);
      await waiter.future;
    }
  }

  bool _mustWaitForOcrAdmission() =>
      mustBlockOcrDuringHeavy || _ocrSessions >= maxOcrSessions;

  void _wakeOcrWaiters() {
    if (_ocrWaiters.isEmpty) {
      return;
    }
    final pending = List<Completer<void>>.from(_ocrWaiters);
    _ocrWaiters.clear();
    for (final waiter in pending) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
  }
}

class ExclusiveGroupBlockedException implements Exception {
  ExclusiveGroupBlockedException(this.reason);

  final String reason;

  @override
  String toString() => 'ExclusiveGroupBlockedException($reason)';
}
