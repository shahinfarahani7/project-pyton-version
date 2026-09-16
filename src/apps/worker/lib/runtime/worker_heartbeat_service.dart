import 'dart:math';

import '../api/worker_api_client.dart';
import 'worker_heartbeat_telemetry.dart';
import 'worker_pipeline_log.dart';

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
  String _workerId;
  String _accessToken;
  int _sequence;

  int get sequence => _sequence;

  void updateCredentials({required String workerId, required String accessToken}) {
    _workerId = workerId;
    _accessToken = accessToken;
  }

  void resetSequence(int sequence) {
    _sequence = max(0, sequence);
  }

  Future<int> send({
    required WorkerHeartbeatTelemetryContext context,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
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
          identityLifecycleView: context.identityLifecycleView,
        ),
      );

      WorkerPipelineLog.info(
        WorkerPipelineLog.heartbeat,
        'POST /workers/$_workerId/heartbeat seq=$nextSequence attempt=${attempt + 1}',
      );

      try {
        await _api.sendHeartbeat(
          workerId: _workerId,
          accessToken: _accessToken,
          body: payload,
          idempotencyKey: 'heartbeat-$nextSequence',
          requestId: 'heartbeat-$nextSequence',
        );
        _sequence = nextSequence;
        WorkerPipelineLog.info(
          WorkerPipelineLog.heartbeat,
          'Heartbeat accepted seq=$nextSequence',
        );
        return _sequence;
      } on WorkerApiException catch (error) {
        if (error.code == 'HEARTBEAT_SEQUENCE_INVALID' && attempt == 0) {
          final synced = _syncSequenceFromDetail(error.detail);
          if (synced) {
            WorkerPipelineLog.info(
              WorkerPipelineLog.heartbeat,
              'Resync heartbeat sequence to $_sequence and retry',
            );
            continue;
          }
        }
        WorkerPipelineLog.error(
          WorkerPipelineLog.heartbeat,
          'Heartbeat rejected (${error.statusCode} ${error.code})',
          error,
        );
        rethrow;
      }
    }

    throw StateError('Heartbeat failed after sequence resync');
  }

  bool _syncSequenceFromDetail(String? detail) {
    final match = RegExp(r'lastSequence=(\d+)').firstMatch(detail ?? '');
    if (match == null) {
      return false;
    }
    _sequence = int.parse(match.group(1)!);
    return true;
  }
}
