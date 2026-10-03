import 'dart:async';
import 'dart:io';

import 'package:edgemint_worker/api/worker_assignment_models.dart';
import 'package:edgemint_worker/runtime/failure_evidence.dart';
import 'package:edgemint_worker/runtime/network_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('transport errors are NETWORK_UNAVAILABLE, not RUNTIME_CRASH', () {
    const mapper = FailureEvidenceMapper();
    final assignment = WorkerAssignment(
      assignmentId: 'asg-123',
      attemptId: 'att-123',
      revisionId: 'rev-123',
      leaseToken: 'lease-token-1234567890',
      fenceToken: 4,
      leaseExpiresAt: DateTime.parse('2026-09-01T10:30:00Z'),
      taskType: 'text.direct',
      modelVersionId: 'mdv-gemma',
      inputManifestUrl: 'https://example/input',
      outputUploadUrl: 'https://example/output',
      startDeadlineAt: DateTime.parse('2026-09-01T10:20:00Z'),
    );
    final errors = <Object>[
      const SocketException('No route to host'),
      TimeoutException('timed out'),
      http.ClientException(
        'Connection refused',
        Uri.parse('http://10.0.2.2:8081'),
      ),
      const SocketException('Failed host lookup'),
      StateError('network unavailable'),
    ];
    for (final error in errors) {
      final evidence = mapper.map(
        assignment: assignment,
        error: error,
        executionTime: const Duration(seconds: 1),
      );
      expect(evidence?.failureCode, ClosedFailureCode.networkUnavailable);
      expect(evidence?.failureCode, isNot(ClosedFailureCode.runtimeCrash));
    }

    final crash = mapper.map(
      assignment: assignment,
      error: StateError('engine crashed'),
      executionTime: Duration.zero,
    );
    expect(crash?.failureCode, ClosedFailureCode.runtimeCrash);
  });

  test('reconnect backoff and connectivity states', () {
    expect(
      ReconnectBackoff.delays.map((delay) => delay.inSeconds).toList(),
      [1, 2, 5, 10, 20, 30],
    );
    expect(ReconnectBackoff.delayForAttempt(0).inSeconds, 1);
    expect(ReconnectBackoff.delayForAttempt(5).inSeconds, 30);
    expect(ReconnectBackoff.delayForAttempt(9).inSeconds, 30);

    final session = ConnectivitySession();
    expect(session.state, ConnectivityState.online);
    session.lost();
    expect(session.state, ConnectivityState.offline);
    expect(session.beginReconnect(), const Duration(seconds: 1));
    expect(session.state, ConnectivityState.reconnecting);
    session.stillOffline();
    expect(session.state, ConnectivityState.offline);
    expect(session.attempt, 1);
    expect(session.beginReconnect(), const Duration(seconds: 2));
    session.restored();
    expect(session.state, ConnectivityState.online);
    expect(session.attempt, 0);
  });

  test('reconcile drops complete after lease expiry or reassignment', () {
    final now = DateTime.utc(2026, 1, 1);
    expect(
      AssignmentSyncReconciler.decide(
        kind: 'complete',
        leaseExpiresAt: DateTime.utc(2020, 1, 1),
        now: now,
        reassigned: false,
      ),
      SyncReplay.dropWithoutComplete,
    );
    expect(
      AssignmentSyncReconciler.decide(
        kind: 'complete',
        leaseExpiresAt: DateTime.utc(2099, 1, 1),
        now: now,
        reassigned: true,
      ),
      SyncReplay.dropWithoutComplete,
    );
    expect(
      AssignmentSyncReconciler.decide(
        kind: 'complete',
        leaseExpiresAt: DateTime.utc(2099, 1, 1),
        now: now,
        reassigned: false,
      ),
      SyncReplay.send,
    );
    expect(
      AssignmentSyncReconciler.decide(
        kind: 'fail',
        leaseExpiresAt: DateTime.utc(2020, 1, 1),
        now: now,
        reassigned: false,
      ),
      SyncReplay.send,
    );
  });
}
