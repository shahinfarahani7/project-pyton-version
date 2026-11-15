import 'device_snapshot.dart';
import 'runtime_safety_controller.dart';

/// Clocks that stay independent of token arrival.
///
/// [silenceTimeout] starts only after the first token. [prefillTimeout] is
/// the wait for that first token. [overallDeadline] covers both.
class GenerationWatch {
  const GenerationWatch({
    this.pollInterval = const Duration(milliseconds: 200),
    this.silenceTimeout = const Duration(seconds: 45),
    this.prefillTimeout = const Duration(minutes: 2),
    this.overallDeadline = const Duration(minutes: 8),
    this.stopConfirmationTimeout = const Duration(seconds: 3),
    this.readSafety,
    this.confirmNativeStop = false,
    this.clock,
  });

  final Duration pollInterval;
  final Duration silenceTimeout;
  final Duration prefillTimeout;
  final Duration overallDeadline;
  final Duration stopConfirmationTimeout;
  final Future<RuntimeSafetyVerdict> Function()? readSafety;
  final bool confirmNativeStop;
  final DateTime Function()? clock;

  DateTime now() => (clock ?? DateTime.now)();
}

class GenerationStopUnconfirmed implements Exception {
  const GenerationStopUnconfirmed(this.reason);

  final String reason;

  @override
  String toString() => 'Native generation stop was not confirmed ($reason)';
}

/// Reads the snapshot's own RAM. A heavy in-flight task with no measurement
/// pauses instead of treating the gap as permission to continue.
RuntimeSafetyVerdict evaluateLiveMemory(
  RuntimeSafetyController controller,
  DeviceSnapshot snapshot,
) {
  final available = snapshot.deviceAvailableRamMb;
  final signals = RuntimeSafetySignals(
    availableMemoryMb: available,
    osMemoryPressure: snapshot.lowMemory == true
        ? OsMemoryPressureLevel.critical
        : OsMemoryPressureLevel.normal,
  );
  if (available == null && snapshot.lowMemory == null) {
    return const RuntimeSafetyVerdict.pause(
      RuntimeSafetyReason.memoryPressure,
      'memory_unmeasured',
    );
  }
  return controller.evaluate(
    snapshot,
    signals: signals,
    heavyTask: true,
    phase: RuntimeSafetyPhase.duringWork,
  );
}
