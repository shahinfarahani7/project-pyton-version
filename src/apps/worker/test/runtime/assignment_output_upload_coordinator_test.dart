import 'package:edgemint_worker/runtime/assignment_output_upload_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AssignmentOutputUploadCoordinator', () {
    test('503 followed by acceptance retries then stops', () {
      final coordinator = AssignmentOutputUploadCoordinator(maxAttempts: 3);
      const assignmentId = 'asg_retry_503';

      expect(coordinator.markInFlight(assignmentId), isTrue);
      coordinator.releaseInFlight(assignmentId);
      expect(coordinator.markInFlight(assignmentId), isTrue);

      expect(coordinator.isRetryableHttpStatus(503), isTrue);
      coordinator.markAccepted(assignmentId);

      expect(coordinator.statusFor(assignmentId),
          AssignmentOutputUploadStatus.accepted);
      expect(coordinator.shouldSkipUpload(assignmentId), isTrue);
      expect(coordinator.markInFlight(assignmentId), isFalse);
    });

    test('timeout leaves upload retryable until attempts exhaust', () {
      final coordinator = AssignmentOutputUploadCoordinator(maxAttempts: 3);
      const assignmentId = 'asg_timeout';

      expect(coordinator.markInFlight(assignmentId), isTrue);
      coordinator.releaseInFlight(assignmentId);
      expect(coordinator.statusFor(assignmentId),
          AssignmentOutputUploadStatus.none);
      expect(coordinator.markInFlight(assignmentId), isTrue);
      coordinator.releaseInFlight(assignmentId);
      expect(coordinator.markInFlight(assignmentId), isTrue);
    });

    test('422 is terminal and blocks further uploads', () {
      final coordinator = AssignmentOutputUploadCoordinator();
      const assignmentId = 'asg_422';

      expect(coordinator.markInFlight(assignmentId), isTrue);
      expect(coordinator.isTerminalHttpStatus(422), isTrue);
      coordinator.markRejectedTerminal(assignmentId);

      expect(coordinator.shouldSkipUpload(assignmentId), isTrue);
      expect(coordinator.markInFlight(assignmentId), isFalse);
    });

    test('concurrent invocation is blocked while in flight', () {
      final coordinator = AssignmentOutputUploadCoordinator();
      const assignmentId = 'asg_concurrent';

      expect(coordinator.markInFlight(assignmentId), isTrue);
      expect(coordinator.markInFlight(assignmentId), isFalse);
      coordinator.markAccepted(assignmentId);
      expect(coordinator.markInFlight(assignmentId), isFalse);
    });

    test('accepted upload with lost response can safely retry once', () {
      final coordinator = AssignmentOutputUploadCoordinator();
      const assignmentId = 'asg_lost_response';

      expect(coordinator.markInFlight(assignmentId), isTrue);
      coordinator.markAccepted(assignmentId);
      expect(coordinator.statusFor(assignmentId),
          AssignmentOutputUploadStatus.accepted);
      expect(coordinator.markInFlight(assignmentId), isFalse);
    });

    test('tasksProcessed gate accepts only once per assignment', () {
      final coordinator = AssignmentOutputUploadCoordinator();
      const assignmentId = 'asg_count_once';
      var tasksProcessed = 0;

      Future<void> recordAcceptedUpload() async {
        if (coordinator.statusFor(assignmentId) ==
            AssignmentOutputUploadStatus.accepted) {
          return;
        }
        if (!coordinator.markInFlight(assignmentId)) {
          return;
        }
        coordinator.markAccepted(assignmentId);
        tasksProcessed += 1;
      }

      return Future(() async {
        await recordAcceptedUpload();
        await recordAcceptedUpload();
        expect(tasksProcessed, 1);
      });
    });

    test('tracked assignments are bounded', () {
      final coordinator = AssignmentOutputUploadCoordinator(
        maxTrackedAssignments: 4,
      );

      for (var index = 0; index < 6; index += 1) {
        final assignmentId = 'asg_bound_$index';
        expect(coordinator.markInFlight(assignmentId), isTrue);
        coordinator.markAccepted(assignmentId);
      }

      expect(coordinator.statusFor('asg_bound_5'),
          AssignmentOutputUploadStatus.accepted);
    });
  });
}
