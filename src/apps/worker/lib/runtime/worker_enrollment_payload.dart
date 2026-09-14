import 'package:edgemint_worker/runtime/device_capability_report.dart';
import 'package:edgemint_worker/runtime/device_snapshot.dart';
import 'package:edgemint_worker/runtime/worker_heartbeat_telemetry.dart';
/// Canonical consent policy version — must match backend settings.
abstract final class WorkerConsentPolicy {
  static const version = '2026-q3-v1';
}

/// Canonical registration payload fields shared by enrollment flows.
abstract final class WorkerEnrollmentPayload {
  static Map<String, dynamic> registration({
    required String installationId,
    required String challengeId,
    required String nonce,
    DeviceSnapshot snapshot = const DeviceSnapshot(
      available: true,
      batteryPercent: 78,
      isCharging: true,
      thermalState: ThermalState.normal,
      network: NetworkKind.wifi,
      freeStorageMb: 20480,
      withinSchedule: true,
      consentsGranted: ['terms', 'privacy', 'resource_use', 'reward_disclosure'],
    ),
    String appVersion = '5.0.0',
    String platform = 'android',
    bool emulator = false,
    String? publicKey,
  }) {
    return {
      'installationId': installationId,
      'platform': platform,
      'appVersion': appVersion,
      'capabilities': DeviceCapabilityReport.fromDispatcher(
        snapshot: snapshot,
        abi: snapshot.isX86Android ? 'x86_64' : 'arm64-v8a',
      ),
      if (publicKey != null) 'publicKey': publicKey,
      'attestation': attestation(
        challengeId: challengeId,
        nonce: nonce,
        emulator: emulator,
      ),
    };
  }

  static Map<String, dynamic> attestation({
    required String challengeId,
    required String nonce,
    bool emulator = false,
    String? publicKeyFingerprint,
  }) {
    return {
      'challengeId': challengeId,
      'nonce': nonce,
      'consentPolicyVersion': WorkerConsentPolicy.version,
      if (emulator) 'emulator': true,
      if (publicKeyFingerprint != null) 'publicKeyFingerprint': publicKeyFingerprint,
    };
  }

  static Map<String, dynamic> heartbeat({
    required int sequence,
    required DeviceSnapshot snapshot,
    List<String> currentLeases = const [],
    List<Map<String, String>> installedModels = const [],
    bool includeCapabilitySnapshot = true,
    int cpuUsageBps = 0,
    List<String> loadedModelIds = const [],
    Map<String, int> runtimeSessions = const {},
    String contributionModeId = 'balanced',
    WorkerCalibrationView? calibrationView,
    WorkerResourceReservationEntry? activeReservation,
  }) {
    return WorkerHeartbeatTelemetry.build(
      WorkerHeartbeatTelemetryContext(
        sequence: sequence,
        snapshot: snapshot,
        currentLeases: currentLeases,
        installedModels: installedModels,
        loadedModelIds: loadedModelIds,
        cpuUsageBps: cpuUsageBps,
        contributionModeId: contributionModeId,
        calibrationView: calibrationView,
        activeReservation: activeReservation,
        runtimeSessionsOverride: runtimeSessions.isEmpty ? null : runtimeSessions,
        includeCapabilitySnapshot: includeCapabilitySnapshot,
      ),
    );
  }
}
