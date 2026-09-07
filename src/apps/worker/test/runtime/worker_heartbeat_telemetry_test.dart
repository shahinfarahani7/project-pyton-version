import 'package:edgemint_worker/runtime/device_snapshot.dart';
import 'package:edgemint_worker/runtime/runtime_exclusive_group_enforcer.dart';
import 'package:edgemint_worker/runtime/worker_heartbeat_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const snapshot = DeviceSnapshot(
    available: true,
    batteryPercent: 78,
    isCharging: true,
    thermalState: ThermalState.normal,
    network: NetworkKind.wifi,
    freeStorageMb: 20480,
    withinSchedule: true,
    consentsGranted: ['terms', 'privacy', 'resource_use', 'reward_disclosure'],
  );

  test('builds Section 39 heartbeat with consent, calibration, and reservations', () {
    final enforcer = RuntimeExclusiveGroupEnforcer();
    final payload = WorkerHeartbeatTelemetry.build(
      WorkerHeartbeatTelemetryContext(
        sequence: 1842,
        snapshot: snapshot,
        currentLeases: ['asg-1'],
        installedModels: const [
          {'modelVersionId': 'mdv_qwen2_5_0_5b', 'artifactSha256': 'abc123'},
        ],
        loadedModelIds: const ['mdv_qwen2_5_0_5b'],
        cpuUsageBps: 2100,
        runtimeExclusiveGroups: enforcer,
        calibrationView: WorkerCalibrationView(
          profileVersion: 1,
          suiteVersion: 'android-arm64-t4-baseline-v1',
          measuredAt: DateTime.utc(2026, 9, 1, 10),
        ),
        activeReservation: WorkerHeartbeatTelemetry.reservationForTask(
          assignmentId: 'asg-1',
          taskType: 'text.summarize',
        ),
        contributionModeId: 'balanced',
      ),
    );

    expect(payload['sequence'], 1842);
    expect(payload['cpuUsageBps'], 2100);
    expect(payload['loadedModelIds'], ['mdv_qwen2_5_0_5b']);
    expect(payload['runtimeSessions'], {'mediapipe_llm': 0, 'paddle_ocr': 0});
    expect(payload['currentLeases'], ['asg-1']);
    expect(payload['consentSnapshot'], {
      'grantedConsents': snapshot.consentsGranted,
      'contributionModeId': 'balanced',
    });
    expect(payload['calibrationView'], {
      'profileVersion': 1,
      'suiteVersion': 'android-arm64-t4-baseline-v1',
      'measuredAt': '2026-09-01T10:00:00.000Z',
    });
    final reservations = payload['resourceReservationsView'] as Map<String, dynamic>;
    expect(reservations['totals'], {
      'cpuUnits': 40,
      'memoryBytes': 1610612736,
      'storageBytes': 0,
    });
    expect(payload['capabilitySnapshot'], isNotNull);
  });
}
