import 'package:edgemint_worker/api/worker_assignment_models.dart';
import 'package:edgemint_worker/runtime/assignment_receiver.dart';
import 'package:edgemint_worker/runtime/device_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

WorkerAssignment _validAssignment({
  String leaseToken = 'lease-token-1234567890',
  int fenceToken = 3,
  DateTime? leaseExpiresAt,
  DateTime? startDeadlineAt,
  String taskType = 'document.ocr',
  String assignmentMode = 'auto',
  bool executionStartsAutomatically = true,
  String inputManifestUrl = 'https://example/input',
  String outputUploadUrl = 'https://example/output',
}) {
  return WorkerAssignment(
    assignmentId: 'asg_test',
    attemptId: 'att_test',
    revisionId: 'rev_test',
    leaseToken: leaseToken,
    fenceToken: fenceToken,
    leaseExpiresAt: leaseExpiresAt ?? DateTime.parse('2026-09-02T14:00:00Z'),
    taskType: taskType,
    modelVersionId: 'mdv_test',
    inputManifestUrl: inputManifestUrl,
    outputUploadUrl: outputUploadUrl,
    startDeadlineAt: startDeadlineAt ?? DateTime.parse('2026-09-02T13:30:00Z'),
    assignmentMode: assignmentMode,
    executionStartsAutomatically: executionStartsAutomatically,
  );
}

const _consentedDevice = DeviceSnapshot(
  available: true,
  batteryPercent: 90,
  isCharging: true,
  thermalState: ThermalState.normal,
  network: NetworkKind.wifi,
  freeStorageMb: 4096,
  withinSchedule: true,
  consentsGranted: ['terms', 'privacy', 'resource_use', 'reward_disclosure'],
);

void main() {
  final receiver = AssignmentReceiver(clock: () => DateTime.parse('2026-09-02T10:00:00Z'));

  group('contract validation', () {
    test('accepts canonical auto assignment contract', () {
      final verdict = receiver.validateContract(_validAssignment());
      expect(verdict.accepted, isTrue);
    });

    test('rejects short lease token', () {
      final verdict = receiver.validateContract(_validAssignment(leaseToken: 'short'));
      expect(verdict.accepted, isFalse);
      expect(verdict.issue!.step, AssignmentValidationStep.contract);
      expect(verdict.issue!.failureCode, 'INPUT_SCHEMA_INVALID');
    });

    test('rejects unsupported task type', () {
      final verdict = receiver.validateContract(_validAssignment(taskType: 'unknown.task'));
      expect(verdict.accepted, isFalse);
      expect(verdict.issue!.failureCode, 'INPUT_RUNTIME_UNSUPPORTED');
    });

    test('rejects expired lease', () {
      final verdict = receiver.validateContract(
        _validAssignment(leaseExpiresAt: DateTime.parse('2026-09-02T09:00:00Z')),
      );
      expect(verdict.accepted, isFalse);
      expect(verdict.issue!.failureCode, 'LEASE_EXPIRED');
      expect(verdict.issue!.retryable, isTrue);
    });

    test('rejects elapsed start deadline', () {
      final verdict = receiver.validateContract(
        _validAssignment(startDeadlineAt: DateTime.parse('2026-09-02T09:30:00Z')),
      );
      expect(verdict.accepted, isFalse);
      expect(verdict.issue!.failureCode, 'START_TIMEOUT');
    });

    test('rejects non-auto assignment mode', () {
      final verdict = receiver.validateContract(_validAssignment(assignmentMode: 'manual'));
      expect(verdict.accepted, isFalse);
      expect(verdict.issue!.failureCode, 'INPUT_SCHEMA_INVALID');
    });
  });

  group('fence validation', () {
    test('accepts matching checkpoint fence', () {
      final verdict = receiver.validateFence(
        assignment: _validAssignment(fenceToken: 4),
        checkpointFenceToken: 4,
      );
      expect(verdict.accepted, isTrue);
    });

    test('rejects stale checkpoint fence', () {
      final verdict = receiver.validateFence(
        assignment: _validAssignment(fenceToken: 4),
        checkpointFenceToken: 2,
      );
      expect(verdict.accepted, isFalse);
      expect(verdict.issue!.step, AssignmentValidationStep.fence);
      expect(verdict.issue!.failureCode, 'POLICY_BLOCKED');
    });
  });

  group('consent validation', () {
    test('accepts required consents', () {
      expect(receiver.validateConsent(_consentedDevice).accepted, isTrue);
    });

    test('rejects missing consent', () {
      const device = DeviceSnapshot(
        available: true,
        batteryPercent: 90,
        isCharging: true,
        thermalState: ThermalState.normal,
        network: NetworkKind.wifi,
        freeStorageMb: 4096,
        withinSchedule: true,
        consentsGranted: ['terms', 'privacy'],
      );
      final verdict = receiver.validateConsent(device);
      expect(verdict.accepted, isFalse);
      expect(verdict.issue!.step, AssignmentValidationStep.consent);
      expect(verdict.issue!.failureCode, 'CONSENT_MISMATCH');
      expect(verdict.issue!.retryable, isFalse);
    });
  });

  test('ensureAccepted throws AssignmentRejectedException', () {
    final verdict = receiver.validateContract(_validAssignment(leaseToken: 'short'));
    expect(
      () => receiver.ensureAccepted(verdict),
      throwsA(isA<AssignmentRejectedException>()),
    );
  });
}
