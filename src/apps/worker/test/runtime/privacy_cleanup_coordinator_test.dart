import 'package:flutter_test/flutter_test.dart';

import 'package:edgemint_worker/runtime/checkpoint_store.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/runtime/privacy_cleanup_coordinator.dart';

CheckpointRecord _record(String assignmentId) {
  return CheckpointRecord(
    assignmentId: assignmentId,
    attemptId: 'att_$assignmentId',
    fenceToken: 1,
    modelVersionId: 'mdv_test',
    modelDigest: 'model_digest',
    inputDigest: 'input_digest',
    sequence: 500,
    progressMilli: 500,
    runtimeStateDigest: 'runtime_digest',
    encryptedBlobRef: 'runtime/chk/$assignmentId',
    savedAt: DateTime.parse('2026-09-06T10:00:00Z'),
  );
}

void main() {
  group('PrivacyCleanupCoordinator', () {
    test('cleans temp blobs and purges checkpoint on normal cleanup', () async {
      final store = InMemoryEncryptedStore();
      final checkpoints = CheckpointStore(store);
      final coordinator = PrivacyCleanupCoordinator();

      coordinator.registerTempBlob(
        assignmentId: 'asg_1',
        blobRef: 'runtime/decode/asg_1',
      );
      coordinator.bindActiveBuffers(assignmentId: 'asg_1');
      await checkpoints.save(_record('asg_1'), [1, 2, 3]);

      final result = await coordinator.cleanupAfterAssignment(
        assignmentId: 'asg_1',
        checkpointStore: checkpoints,
      );

      expect(result.removedTempRefs, contains('runtime/decode/asg_1'));
      expect(result.checkpointPurged, isTrue);
      expect(result.buffersReset, isTrue);
      expect(await checkpoints.latestFor('asg_1'), isNull);
    });

    test('preserves checkpoint when resume grant active', () async {
      final store = InMemoryEncryptedStore();
      final checkpoints = CheckpointStore(store);
      final coordinator = PrivacyCleanupCoordinator()..markResumeGrantActive(assignmentId: 'asg_2');

      await checkpoints.save(_record('asg_2'), [4, 5]);

      final result = await coordinator.cleanupAfterAssignment(
        assignmentId: 'asg_2',
        checkpointStore: checkpoints,
        preserveCheckpoint: true,
      );

      expect(result.checkpointPurged, isFalse);
      expect(await checkpoints.latestFor('asg_2'), isNotNull);
    });

    test('detects cross-task buffer leakage risk', () async {
      final coordinator = PrivacyCleanupCoordinator();
      coordinator.bindActiveBuffers(assignmentId: 'asg_prev');
      expect(coordinator.wouldLeakIntoNextAssignment('asg_next'), isTrue);
      await coordinator.cleanupAfterAssignment(
        assignmentId: 'asg_prev',
        checkpointStore: CheckpointStore(InMemoryEncryptedStore()),
      );
      expect(coordinator.wouldLeakIntoNextAssignment('asg_next'), isFalse);
    });
  });
}
