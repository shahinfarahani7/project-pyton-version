import 'package:edgemint_worker/runtime/assignment_inbox.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/api/worker_assignment_models.dart';
import 'package:test/test.dart';

WorkerAssignment _assignment({int fenceToken = 3, String assignmentId = 'asg_1'}) => WorkerAssignment(
      assignmentId: assignmentId,
      attemptId: 'att_1',
      revisionId: 'rev_1',
      leaseToken: 'lease-token-1234567890',
      fenceToken: fenceToken,
      leaseExpiresAt: DateTime.utc(2026, 9, 6, 12),
      taskType: 'text-summarize',
      modelVersionId: 'mdv_1',
      inputManifestUrl: 'https://worker.example/assignments/$assignmentId/input-manifest',
      outputUploadUrl: 'https://worker.example/assignments/$assignmentId/output',
      startDeadlineAt: DateTime.utc(2026, 9, 6, 11, 30),
      deliveryInboxId: 'del_1',
    );

void main() {
  test('duplicate delivery with same fence is replay-safe', () async {
    final inbox = AssignmentInbox(store: InMemoryEncryptedStore());
    final assignment = _assignment();

    final first = await inbox.recordBeforeProcess(assignment);
    final second = await inbox.recordBeforeProcess(assignment);

    expect(first.disposition, AssignmentInboxDisposition.accepted);
    expect(second.disposition, AssignmentInboxDisposition.duplicateReplay);
  });

  test('stale fence is rejected when newer fence exists locally', () async {
    final inbox = AssignmentInbox(store: InMemoryEncryptedStore());
    await inbox.recordBeforeProcess(_assignment(fenceToken: 5));

    final receipt = await inbox.recordBeforeProcess(_assignment(fenceToken: 3));

    expect(receipt.disposition, AssignmentInboxDisposition.staleFenceSuperseded);
  });

  test('bootstrap reconciliation merges server entries', () async {
    final inbox = AssignmentInbox(store: InMemoryEncryptedStore());
    await inbox.recordBeforeProcess(_assignment(assignmentId: 'asg_local'));

    final merged = await inbox.reconcileBootstrap(
      serverEntries: [
        AssignmentInboxEntry(
          assignmentId: 'asg_server',
          attemptId: 'att_server',
          fenceToken: 2,
          recordedAt: DateTime.utc(2026, 9, 6, 10),
        ),
      ],
    );

    expect(merged.length, 2);
    expect(merged.any((entry) => entry.assignmentId == 'asg_local'), isTrue);
    expect(merged.any((entry) => entry.assignmentId == 'asg_server'), isTrue);
  });
}
