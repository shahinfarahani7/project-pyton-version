import 'package:edgemint_worker/runtime/execution_stop_tracker.dart';
import 'package:test/test.dart';

void main() {
  test('stop requested precedes stop confirmed', () {
    final tracker = ExecutionStopTracker(clock: () => DateTime.utc(2026, 9, 6, 10));
    tracker.requestStop();
    expect(tracker.stopRequestedAt, isNotNull);
    expect(tracker.stopConfirmedAt, isNull);
    expect(tracker.isStopConfirmed, isFalse);

    tracker.confirmStop(proof: 'proof-1');
    expect(tracker.stopConfirmedAt, isNotNull);
    expect(tracker.isStopConfirmed, isTrue);
    expect(tracker.proof, 'proof-1');
  });

  test('physical release proof is deterministic', () {
    final proof = buildPhysicalReleaseProof(
      assignmentId: 'asg_test',
      fenceToken: 7,
      cleanupPhase: 'cleanup',
    );
    expect(proof, 'asg_test|7|cleanup|stop_confirmed');
  });
}
