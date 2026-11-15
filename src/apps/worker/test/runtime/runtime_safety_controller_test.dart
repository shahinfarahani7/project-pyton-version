import 'dart:io';

import 'package:edgemint_worker/runtime/device_snapshot.dart';
import 'package:edgemint_worker/runtime/runtime_safety_controller.dart';
import 'package:flutter_test/flutter_test.dart';

DeviceSnapshot _snapshot({ThermalState thermal = ThermalState.normal}) {
  return DeviceSnapshot(
    available: true,
    batteryPercent: 80,
    isCharging: true,
    thermalState: thermal,
    network: NetworkKind.wifi,
    freeStorageMb: 4096,
    withinSchedule: true,
    consentsGranted: const ['terms', 'privacy', 'resource_use', 'reward_disclosure'],
  );
}

void main() {
  test('execute when device is nominal', () {
    const controller = RuntimeSafetyController();
    final verdict = controller.evaluate(_snapshot());
    expect(verdict.decision, RuntimeSafetyDecision.execute);
    expect(verdict.mayExecute, isTrue);
  });

  test('defer heavy work when thermal is throttled before execution', () {
    const controller = RuntimeSafetyController();
    final verdict = controller.evaluate(
      _snapshot(thermal: ThermalState.throttled),
      heavyTask: false,
      phase: RuntimeSafetyPhase.beforeWork,
    );
    expect(verdict.decision, RuntimeSafetyDecision.deferForSafety);
    expect(verdict.reason, RuntimeSafetyReason.thermalThrottled);
    expect(verdict.telemetryCode, 'THERMAL_THROTTLED');
  });

  test('pause during work when thermal becomes throttled', () {
    const controller = RuntimeSafetyController();
    final verdict = controller.evaluate(
      _snapshot(thermal: ThermalState.throttled),
      phase: RuntimeSafetyPhase.duringWork,
    );
    expect(verdict.decision, RuntimeSafetyDecision.pauseForSafety);
  });

  test('defer before work on moderate memory pressure', () {
    const controller = RuntimeSafetyController();
    final verdict = controller.evaluate(
      _snapshot(),
      signals: const RuntimeSafetySignals(availableMemoryMb: 700),
      phase: RuntimeSafetyPhase.beforeWork,
    );
    expect(verdict.decision, RuntimeSafetyDecision.deferForSafety);
    expect(verdict.reason, RuntimeSafetyReason.memoryPressure);
  });

  test('abort when OS memory pressure is critical', () {
    const controller = RuntimeSafetyController();
    final verdict = controller.evaluate(
      _snapshot(),
      signals: const RuntimeSafetySignals(osMemoryPressure: OsMemoryPressureLevel.critical),
    );
    expect(verdict.decision, RuntimeSafetyDecision.abortForSafety);
    expect(verdict.telemetryCode, 'OS_PRESSURE');
  });

  test('abort when runtime corruption is reported', () {
    const controller = RuntimeSafetyController();
    final verdict = controller.evaluate(
      _snapshot(),
      signals: const RuntimeSafetySignals(runtimeCorrupted: true),
    );
    expect(verdict.decision, RuntimeSafetyDecision.abortForSafety);
    expect(verdict.reason, RuntimeSafetyReason.runtimeCorrupted);
  });

  test('ensureExecuteOrThrow raises for defer verdict', () {
    const controller = RuntimeSafetyController();
    expect(
      () => controller.ensureExecuteOrThrow(_snapshot(thermal: ThermalState.critical)),
      throwsA(isA<RuntimeSafetyException>()),
    );
  });

  test('during work uses the snapshot RAM and pauses when it was not measured', () {
    const controller = RuntimeSafetyController();
    final measured = controller.evaluate(
      DeviceSnapshot(
        available: true,
        batteryPercent: 80,
        isCharging: true,
        thermalState: ThermalState.normal,
        network: NetworkKind.wifi,
        freeStorageMb: 4096,
        withinSchedule: true,
        consentsGranted: const ['terms'],
        deviceAvailableRamMb: 100,
        deviceTotalRamMb: 4096,
      ),
      heavyTask: true,
      phase: RuntimeSafetyPhase.duringWork,
    );
    expect(measured.decision, RuntimeSafetyDecision.abortForSafety);
    final unknown = controller.evaluate(
      _snapshot(),
      heavyTask: true,
      phase: RuntimeSafetyPhase.duringWork,
    );
    expect(unknown.decision, RuntimeSafetyDecision.pauseForSafety);
    expect(unknown.detail, 'memory_unmeasured');
  });

  test('runtime safety module avoids forbidden local scheduler tokens', () {
    final source = File('lib/runtime/runtime_safety_controller.dart').readAsStringSync();
    for (final token in const [
      'LocalTaskSelector',
      'LocalRetryOrchestrator',
      'LocalReassignmentManager',
      'LocalCloudFallbackDecision',
    ]) {
      expect(source.contains(token), isFalse, reason: token);
    }
  });
}
