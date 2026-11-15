import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'encrypted_store.dart';

/// One process lifetime. A new process gets a new id, so a stored record
/// with a different id is an execution that did not finish here.
abstract final class ProcessRun {
  static final String id = _create();

  static String _create() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}

class ActiveExecutionRecord {
  const ActiveExecutionRecord({
    required this.processRunId,
    required this.assignmentId,
    required this.attemptId,
    required this.fenceToken,
    required this.phase,
    required this.startedAt,
    required this.leaseExpiresAt,
    this.supportsResume = false,
    this.checkpointId,
    this.checkpointValid = false,
  });

  final String processRunId;
  final String assignmentId;
  final String attemptId;
  final int fenceToken;
  final String phase;
  final DateTime startedAt;
  final DateTime leaseExpiresAt;
  final bool supportsResume;
  final String? checkpointId;
  final bool checkpointValid;

  Map<String, dynamic> toJson() => {
        'processRunId': processRunId,
        'assignmentId': assignmentId,
        'attemptId': attemptId,
        'fenceToken': fenceToken,
        'phase': phase,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'leaseExpiresAt': leaseExpiresAt.toUtc().toIso8601String(),
        'supportsResume': supportsResume,
        if (checkpointId != null) 'checkpointId': checkpointId,
        'checkpointValid': checkpointValid,
      };

  static ActiveExecutionRecord? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    final started = DateTime.tryParse(json['startedAt'] as String? ?? '');
    final lease = DateTime.tryParse(json['leaseExpiresAt'] as String? ?? '');
    final assignmentId = json['assignmentId'] as String?;
    final attemptId = json['attemptId'] as String?;
    final fence = json['fenceToken'];
    if (started == null ||
        lease == null ||
        assignmentId == null ||
        attemptId == null ||
        fence is! int) {
      return null;
    }
    return ActiveExecutionRecord(
      processRunId: json['processRunId'] as String? ?? '',
      assignmentId: assignmentId,
      attemptId: attemptId,
      fenceToken: fence,
      phase: json['phase'] as String? ?? 'before_inference',
      startedAt: started.toUtc(),
      leaseExpiresAt: lease.toUtc(),
      supportsResume: json['supportsResume'] == true,
      checkpointId: json['checkpointId'] as String?,
      checkpointValid: json['checkpointValid'] == true,
    );
  }
}

class ProcessExitEvidence {
  const ProcessExitEvidence({
    required this.reasonName,
    required this.classification,
    required this.timestamp,
    this.status,
  });

  final String reasonName;
  final String classification;
  final DateTime timestamp;
  final int? status;

  Map<String, dynamic> toJson() => {
        'reasonName': reasonName,
        'classification': classification,
        'timestamp': timestamp.toUtc().toIso8601String(),
        if (status != null) 'status': status,
      };
}

/// ApplicationExitInfo reason names from the platform channel.
/// SIGKILL / signaled is not classified as OOM.
String classifyProcessExit({required String? reasonName, int? status}) {
  switch (reasonName) {
    case 'low_memory':
      return 'platform_low_memory';
    case 'anr':
      return 'anr';
    case 'crash':
      return 'crash';
    case 'native_crash':
      return 'native_crash';
    case 'signaled':
      return 'signaled_not_oom';
    case 'user_requested':
    case 'exit_self':
      return reasonName!;
    default:
      return 'unknown';
  }
}

ProcessExitEvidence? matchProcessExit({
  required List<Map<String, dynamic>> exits,
  required DateTime startedAt,
}) {
  ProcessExitEvidence? best;
  for (final exit in exits) {
    final timestampMs = exit['timestamp'];
    if (timestampMs is! int) {
      continue;
    }
    final timestamp = DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true);
    if (timestamp.isBefore(startedAt.toUtc().subtract(const Duration(seconds: 2)))) {
      continue;
    }
    final reasonName = exit['reasonName'] as String? ?? 'unknown';
    final status = exit['status'] as int?;
    final evidence = ProcessExitEvidence(
      reasonName: reasonName,
      classification: classifyProcessExit(reasonName: reasonName, status: status),
      timestamp: timestamp,
      status: status,
    );
    if (best == null || evidence.timestamp.isBefore(best.timestamp)) {
      best = evidence;
    }
  }
  return best;
}

enum InterruptionDisposition { report, dropExpired, dropReassigned, dropTerminal }

const _terminalServerStatuses = {
  'completed',
  'cancelled',
  'failed',
  'expired',
  'revoked',
  'stale',
};

InterruptionDisposition planInterruption({
  required DateTime? leaseExpiresAt,
  required DateTime now,
  required bool reassigned,
  String? serverStatus,
}) {
  if (reassigned || serverStatus == 'reassigned') {
    return InterruptionDisposition.dropReassigned;
  }
  if (serverStatus != null && _terminalServerStatuses.contains(serverStatus)) {
    return InterruptionDisposition.dropTerminal;
  }
  if (leaseExpiresAt != null && !leaseExpiresAt.toUtc().isAfter(now.toUtc())) {
    return InterruptionDisposition.dropExpired;
  }
  return InterruptionDisposition.report;
}

bool resumePermitted(ActiveExecutionRecord record) =>
    record.supportsResume &&
    record.checkpointValid &&
    record.checkpointId != null &&
    record.checkpointId!.isNotEmpty;

class ActiveExecutionJournal {
  ActiveExecutionJournal({required EncryptedStore store}) : _store = store;

  static const storageKey = 'active_execution_v1';

  final EncryptedStore _store;

  Future<void> save(ActiveExecutionRecord record) async {
    await _store.write(
      storageKey,
      Uint8List.fromList(utf8.encode(jsonEncode(record.toJson()))),
    );
  }

  Future<ActiveExecutionRecord?> read() async {
    final bytes = await _store.read(storageKey);
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      return null;
    }
    return ActiveExecutionRecord.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<void> clear() async {
    await _store.delete(storageKey);
  }
}

String interruptionIdempotencyKey(ActiveExecutionRecord record) =>
    'interrupt-${record.assignmentId}-${record.fenceToken}';

/// Fail payload for the existing outbox. The lease token stays in [body]
/// because the fail API requires it. Diagnostics omit the token and the prompt.
Map<String, dynamic> interruptionOutboxPayload({
  required ActiveExecutionRecord record,
  required String leaseToken,
  ProcessExitEvidence? exitInfo,
}) {
  return {
    'kind': 'fail',
    'assignmentId': record.assignmentId,
    'leaseExpiresAt': record.leaseExpiresAt.toUtc().toIso8601String(),
    'outcome': 'pending',
    'reassigned': false,
    'body': {
      'leaseToken': leaseToken,
      'fenceToken': record.fenceToken,
      'errorCode': 'OS_PROCESS_TERMINATED',
      'retryable': true,
      'diagnostics': {
        'assignmentId': record.assignmentId,
        'attemptId': record.attemptId,
        'processRunId': record.processRunId,
        'phase': record.phase,
        'observedAt': record.startedAt.toUtc().toIso8601String(),
        'exitClassification': exitInfo?.classification ?? 'unknown',
        'exitReason': exitInfo?.reasonName ?? 'unknown',
        if (exitInfo != null)
          'exitTimestamp': exitInfo.timestamp.toUtc().toIso8601String(),
      },
    },
  };
}
