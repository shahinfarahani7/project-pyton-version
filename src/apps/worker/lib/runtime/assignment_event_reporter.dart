import 'dart:convert';

import '../api/worker_api_client.dart';
import '../api/worker_assignment_models.dart';
import 'checkpoint_manager.dart';
import 'execution_plan_runner.dart';
import 'execution_policy.dart';
import 'transport_recovery_journal.dart';

/// Streams assignment progress and checkpoint commands to the server with fence tokens.
///
/// Ordering contract (must match backend `AssignmentCommandService`):
/// - progress aggregate band: `fenceToken * 1e9 + 2_000_000 + sequence`
/// - checkpoint aggregate band: `fenceToken * 1e9 + 3_000_000 + sequence`
/// - worker `sequence` counters are monotonic per assignment attempt
class AssignmentEventReporter {
  AssignmentEventReporter({
    required WorkerApiClient api,
    required WorkerAssignment assignment,
    required String accessToken,
    required String inputSha256,
    TransportRecoveryJournal? transportJournal,
  })  : _api = api,
        _assignment = assignment,
        _accessToken = accessToken,
        _inputSha256 = inputSha256,
        _transportJournal = transportJournal ?? TransportRecoveryJournal();

  final WorkerApiClient _api;
  final WorkerAssignment _assignment;
  final String _accessToken;
  final String _inputSha256;
  final TransportRecoveryJournal _transportJournal;

  TransportRecoveryJournal get transportJournal => _transportJournal;

  int _progressSequence = 0;
  int _checkpointSequence = 0;
  int _lastReportedProgressMilli = 0;

  int get progressSequence => _progressSequence;

  int get checkpointSequence => _checkpointSequence;

  Future<void> reportPlanProgress(ExecutionPlanProgressEvent event) async {
    if (event.progressMilli < 1000 &&
        event.progressMilli - _lastReportedProgressMilli <
            ExecutionPolicy.minimumProgressDeltaMilli) {
      return;
    }

    _progressSequence += 1;
    final idempotencyKey =
        'progress-${_assignment.attemptId}-${event.stage.name}-${event.progressMilli}';
    final body = {
      'leaseToken': _assignment.leaseToken,
      'fenceToken': _assignment.fenceToken,
      'sequence': _progressSequence,
      'stage': event.stage.name,
      'progressBps': event.progressMilli * 10,
      'metrics': {
        'stageIndex': event.stageIndex,
        'stageCount': event.stageCount,
        'operation': event.stage.operation,
        if (event.stage.runtimeClass != null)
          'runtimeClass': event.stage.runtimeClass,
      },
    };
    _transportJournal.record(
      TransportJournalEntry(
        assignmentId: _assignment.assignmentId,
        eventKind: 'progress',
        idempotencyKey: idempotencyKey,
        path: '/assignments/${_assignment.assignmentId}:progress',
        bodyJson: jsonEncode(body),
        recordedAt: DateTime.now().toUtc(),
      ),
    );
    await _api.progressAssignment(
      assignmentId: _assignment.assignmentId,
      accessToken: _accessToken,
      idempotencyKey: idempotencyKey,
      body: body,
    );
    _transportJournal.acknowledge(idempotencyKey);
    _lastReportedProgressMilli = event.progressMilli;
  }

  Future<void> reportChunkCheckpoint(ChunkCheckpointRecord record) async {
    _checkpointSequence += 1;
    final blobRef =
        'runtime/chunk_checkpoints/${record.assignmentId}/${record.chunkIndex}';
    final idempotencyKey =
        'checkpoint-${_assignment.attemptId}-chunk-${record.chunkIndex}';
    final body = {
      'leaseToken': _assignment.leaseToken,
      'fenceToken': _assignment.fenceToken,
      'sequence': _checkpointSequence,
      'modelVersionId': record.modelVersionId,
      'inputSha256': _inputSha256,
      'checkpointSha256': record.summaryHash,
      'encryptedBlobRef': blobRef,
      'chunkIndex': record.chunkIndex,
    };
    _transportJournal.record(
      TransportJournalEntry(
        assignmentId: _assignment.assignmentId,
        eventKind: 'checkpoint',
        idempotencyKey: idempotencyKey,
        path: '/assignments/${_assignment.assignmentId}:checkpoint',
        bodyJson: jsonEncode(body),
        recordedAt: DateTime.now().toUtc(),
      ),
    );
    await _api.checkpointAssignment(
      assignmentId: _assignment.assignmentId,
      accessToken: _accessToken,
      idempotencyKey: idempotencyKey,
      body: body,
    );
    _transportJournal.acknowledge(idempotencyKey);
  }

  Future<int> retransmitPendingTransport() => _transportJournal.retransmitPending();
}
