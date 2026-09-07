import 'device_snapshot.dart';

/// Canonical worker safety decisions (Architecture Section 18).
enum RuntimeSafetyDecision {
  execute,
  deferForSafety,
  pauseForSafety,
  abortForSafety,
}

enum RuntimeSafetyReason {
  thermalCritical,
  thermalThrottled,
  memoryPressure,
  osPressure,
  runtimeCorrupted,
}

enum OsMemoryPressureLevel { normal, moderate, critical }

/// Optional runtime signals not yet present on every [DeviceSnapshot].
class RuntimeSafetySignals {
  const RuntimeSafetySignals({
    this.availableMemoryMb,
    this.osMemoryPressure = OsMemoryPressureLevel.normal,
    this.runtimeCorrupted = false,
  });

  final int? availableMemoryMb;
  final OsMemoryPressureLevel osMemoryPressure;
  final bool runtimeCorrupted;

  static const none = RuntimeSafetySignals();
}

enum RuntimeSafetyPhase { beforeWork, duringWork }

class RuntimeSafetyVerdict {
  const RuntimeSafetyVerdict.execute()
      : decision = RuntimeSafetyDecision.execute,
        reason = null,
        detail = null;

  const RuntimeSafetyVerdict._(
    this.decision,
    this.reason, [
    this.detail,
  ]);

  const RuntimeSafetyVerdict.defer(RuntimeSafetyReason reason, [String? detail])
      : this._(RuntimeSafetyDecision.deferForSafety, reason, detail);

  const RuntimeSafetyVerdict.pause(RuntimeSafetyReason reason, [String? detail])
      : this._(RuntimeSafetyDecision.pauseForSafety, reason, detail);

  const RuntimeSafetyVerdict.abort(RuntimeSafetyReason reason, [String? detail])
      : this._(RuntimeSafetyDecision.abortForSafety, reason, detail);

  final RuntimeSafetyDecision decision;
  final RuntimeSafetyReason? reason;
  final String? detail;

  bool get mayExecute => decision == RuntimeSafetyDecision.execute;

  String get telemetryCode => switch (reason) {
        RuntimeSafetyReason.thermalCritical => 'THERMAL_CRITICAL',
        RuntimeSafetyReason.thermalThrottled => 'THERMAL_THROTTLED',
        RuntimeSafetyReason.memoryPressure => 'MEMORY_PRESSURE',
        RuntimeSafetyReason.osPressure => 'OS_PRESSURE',
        RuntimeSafetyReason.runtimeCorrupted => 'RUNTIME_CORRUPTED',
        null => 'SAFETY_OK',
      };
}

/// Local machine-safety gate for OOM/thermal/OS pressure deferral.
///
/// Does not schedule, retry, reassign, or select tasks locally.
class RuntimeSafetyController {
  const RuntimeSafetyController({
    this.deferMemoryHeadroomMb = 768,
    this.pauseMemoryHeadroomMb = 512,
    this.abortMemoryHeadroomMb = 256,
  });

  final int deferMemoryHeadroomMb;
  final int pauseMemoryHeadroomMb;
  final int abortMemoryHeadroomMb;

  RuntimeSafetyVerdict evaluate(
    DeviceSnapshot snapshot, {
    RuntimeSafetySignals signals = RuntimeSafetySignals.none,
    bool heavyTask = false,
    RuntimeSafetyPhase phase = RuntimeSafetyPhase.beforeWork,
  }) {
    if (signals.runtimeCorrupted) {
      return const RuntimeSafetyVerdict.abort(
        RuntimeSafetyReason.runtimeCorrupted,
        'Runtime or model state is corrupted',
      );
    }

    final memoryVerdict = _evaluateMemory(signals, phase: phase);
    if (memoryVerdict != null) {
      return memoryVerdict;
    }

    final osVerdict = _evaluateOsPressure(signals, phase: phase);
    if (osVerdict != null) {
      return osVerdict;
    }

    return _evaluateThermal(snapshot, heavyTask: heavyTask, phase: phase);
  }

  void ensureExecuteOrThrow(
    DeviceSnapshot snapshot, {
    RuntimeSafetySignals signals = RuntimeSafetySignals.none,
    bool heavyTask = false,
    RuntimeSafetyPhase phase = RuntimeSafetyPhase.beforeWork,
  }) {
    final verdict = evaluate(
      snapshot,
      signals: signals,
      heavyTask: heavyTask,
      phase: phase,
    );
    if (!verdict.mayExecute) {
      throw RuntimeSafetyException(verdict);
    }
  }

  RuntimeSafetyVerdict? _evaluateMemory(
    RuntimeSafetySignals signals, {
    required RuntimeSafetyPhase phase,
  }) {
    final available = signals.availableMemoryMb;
    if (available == null) {
      return null;
    }
    if (available <= abortMemoryHeadroomMb) {
      return RuntimeSafetyVerdict.abort(
        RuntimeSafetyReason.memoryPressure,
        'Available memory ${available}MB <= abort threshold ${abortMemoryHeadroomMb}MB',
      );
    }
    if (phase == RuntimeSafetyPhase.duringWork && available <= pauseMemoryHeadroomMb) {
      return RuntimeSafetyVerdict.pause(
        RuntimeSafetyReason.memoryPressure,
        'Available memory ${available}MB <= pause threshold ${pauseMemoryHeadroomMb}MB',
      );
    }
    if (available <= deferMemoryHeadroomMb) {
      return phase == RuntimeSafetyPhase.beforeWork
          ? RuntimeSafetyVerdict.defer(
              RuntimeSafetyReason.memoryPressure,
              'Available memory ${available}MB <= defer threshold ${deferMemoryHeadroomMb}MB',
            )
          : RuntimeSafetyVerdict.pause(
              RuntimeSafetyReason.memoryPressure,
              'Available memory ${available}MB <= defer threshold ${deferMemoryHeadroomMb}MB',
            );
    }
    return null;
  }

  RuntimeSafetyVerdict? _evaluateOsPressure(
    RuntimeSafetySignals signals, {
    required RuntimeSafetyPhase phase,
  }) {
    return switch (signals.osMemoryPressure) {
      OsMemoryPressureLevel.normal => null,
      OsMemoryPressureLevel.moderate => phase == RuntimeSafetyPhase.beforeWork
          ? const RuntimeSafetyVerdict.defer(
              RuntimeSafetyReason.osPressure,
              'OS memory pressure moderate',
            )
          : const RuntimeSafetyVerdict.pause(
              RuntimeSafetyReason.osPressure,
              'OS memory pressure moderate',
            ),
      OsMemoryPressureLevel.critical => const RuntimeSafetyVerdict.abort(
          RuntimeSafetyReason.osPressure,
          'OS memory pressure critical',
        ),
    };
  }

  RuntimeSafetyVerdict _evaluateThermal(
    DeviceSnapshot snapshot, {
    required bool heavyTask,
    required RuntimeSafetyPhase phase,
  }) {
    return switch (snapshot.thermalState) {
      ThermalState.critical => phase == RuntimeSafetyPhase.beforeWork
          ? const RuntimeSafetyVerdict.defer(
              RuntimeSafetyReason.thermalCritical,
              'Thermal state critical',
            )
          : const RuntimeSafetyVerdict.pause(
              RuntimeSafetyReason.thermalCritical,
              'Thermal state critical',
            ),
      ThermalState.throttled => phase == RuntimeSafetyPhase.beforeWork
          ? const RuntimeSafetyVerdict.defer(
              RuntimeSafetyReason.thermalThrottled,
              'Thermal state throttled',
            )
          : const RuntimeSafetyVerdict.pause(
              RuntimeSafetyReason.thermalThrottled,
              'Thermal state throttled',
            ),
      ThermalState.warm when heavyTask && phase == RuntimeSafetyPhase.beforeWork =>
        const RuntimeSafetyVerdict.defer(
          RuntimeSafetyReason.thermalThrottled,
          'Thermal state warm for heavy task',
        ),
      ThermalState.warm when heavyTask && phase == RuntimeSafetyPhase.duringWork =>
        const RuntimeSafetyVerdict.pause(
          RuntimeSafetyReason.thermalThrottled,
          'Thermal state warm for heavy task',
        ),
      _ => const RuntimeSafetyVerdict.execute(),
    };
  }
}

class RuntimeSafetyException implements Exception {
  RuntimeSafetyException(this.verdict);

  final RuntimeSafetyVerdict verdict;

  @override
  String toString() => 'RuntimeSafetyException(${verdict.decision}, ${verdict.telemetryCode})';
}
