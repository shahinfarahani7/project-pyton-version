import 'dart:math';

import '../api/worker_api_client.dart';
import 'worker_heartbeat_telemetry.dart';

/// Sends monotonic worker heartbeats for server-side reconciliation (Section 39–40).
class WorkerHeartbeatService {
  WorkerHeartbeatService({
    required WorkerApiClient api,
    required String workerId,
    required String accessToken,
    int initialSequence = 0,
  })  : _api = api,
        _workerId = workerId,
        _accessToken = accessToken,
        _sequence = initialSequence;

  final WorkerApiClient _api;
  final String _workerId;
  final String _accessToken;
  int _sequence;

  int get sequence => _sequence;

  Future<void> send({
    required WorkerHeartbeatTelemetryContext context,
  }) async {
    final nextSequence = max(_sequence + 1, context.sequence);
    final payload = WorkerHeartbeatTelemetry.build(
      WorkerHeartbeatTelemetryContext(
        sequence: nextSequence,
        snapshot: context.snapshot,
        currentLeases: context.currentLeases,
        installedModels: context.installedModels,
        loadedModelIds: context.loadedModelIds,
        cpuUsageBps: context.cpuUsageBps,
        runtimeExclusiveGroups: context.runtimeExclusiveGroups,
        runtimeSessionsOverride: context.runtimeSessionsOverride,
        calibrationView: context.calibrationView,
        activeReservation: context.activeReservation,
        contributionModeId: context.contributionModeId,
        includeCapabilitySnapshot: context.includeCapabilitySnapshot,
      ),
    );

    await _api.sendHeartbeat(
      workerId: _workerId,
      accessToken: _accessToken,
      body: payload,
      idempotencyKey: 'heartbeat-$nextSequence',
      requestId: 'heartbeat-$nextSequence',
    );
    _sequence = nextSequence;
  }
}
