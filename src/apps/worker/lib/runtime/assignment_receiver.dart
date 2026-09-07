import '../api/worker_assignment_models.dart';
import '../tasks/task_type_mapper.dart';
import 'device_snapshot.dart';
import 'execution_policy.dart';

enum AssignmentValidationStep {
  contract,
  fence,
  consent,
}

class AssignmentValidationIssue {
  const AssignmentValidationIssue({
    required this.step,
    required this.failureCode,
    required this.retryable,
    required this.detail,
  });

  final AssignmentValidationStep step;
  final String failureCode;
  final bool retryable;
  final String detail;
}

class AssignmentReceiverVerdict {
  const AssignmentReceiverVerdict.accept()
      : accepted = true,
        issue = null;

  const AssignmentReceiverVerdict.rejected(this.issue) : accepted = false;

  final bool accepted;
  final AssignmentValidationIssue? issue;
}

class AssignmentRejectedException implements Exception {
  AssignmentRejectedException(this.issue);

  final AssignmentValidationIssue issue;

  String get failureCode => issue.failureCode;
  bool get retryable => issue.retryable;
  AssignmentValidationStep get step => issue.step;

  @override
  String toString() => 'AssignmentRejectedException(${issue.step}, ${issue.failureCode}, ${issue.detail})';
}

/// Section 8 gate: contract, fence, and consent validation before execution.
class AssignmentReceiver {
  AssignmentReceiver({
    DateTime Function()? clock,
    this.minimumLeaseTokenLength = 16,
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final int minimumLeaseTokenLength;

  AssignmentReceiverVerdict validateContract(WorkerAssignment assignment) {
    if (_isBlank(assignment.assignmentId) ||
        _isBlank(assignment.attemptId) ||
        _isBlank(assignment.revisionId)) {
      return _reject(
        step: AssignmentValidationStep.contract,
        failureCode: 'INPUT_SCHEMA_INVALID',
        retryable: false,
        detail: 'assignment identity fields are required',
      );
    }
    if (assignment.leaseToken.length < minimumLeaseTokenLength) {
      return _reject(
        step: AssignmentValidationStep.contract,
        failureCode: 'INPUT_SCHEMA_INVALID',
        retryable: false,
        detail: 'leaseToken is too short',
      );
    }
    if (assignment.fenceToken < 1) {
      return _reject(
        step: AssignmentValidationStep.contract,
        failureCode: 'INPUT_SCHEMA_INVALID',
        retryable: false,
        detail: 'fenceToken must be >= 1',
      );
    }
    if (_isBlank(assignment.taskType) || !_isSupportedTaskType(assignment.taskType)) {
      return _reject(
        step: AssignmentValidationStep.contract,
        failureCode: 'INPUT_RUNTIME_UNSUPPORTED',
        retryable: false,
        detail: 'unsupported taskType ${assignment.taskType}',
      );
    }
    if (_isBlank(assignment.modelVersionId)) {
      return _reject(
        step: AssignmentValidationStep.contract,
        failureCode: 'INPUT_SCHEMA_INVALID',
        retryable: false,
        detail: 'modelVersionId is required',
      );
    }
    if (!_isHttpUrl(assignment.inputManifestUrl) || !_isHttpUrl(assignment.outputUploadUrl)) {
      return _reject(
        step: AssignmentValidationStep.contract,
        failureCode: 'INPUT_SCHEMA_INVALID',
        retryable: false,
        detail: 'assignment URLs must be absolute http(s) URIs',
      );
    }
    if (assignment.assignmentMode != 'auto') {
      return _reject(
        step: AssignmentValidationStep.contract,
        failureCode: 'INPUT_SCHEMA_INVALID',
        retryable: false,
        detail: 'assignmentMode must be auto',
      );
    }
    if (!assignment.executionStartsAutomatically) {
      return _reject(
        step: AssignmentValidationStep.contract,
        failureCode: 'INPUT_SCHEMA_INVALID',
        retryable: false,
        detail: 'executionStartsAutomatically must be true',
      );
    }

    final now = _clock().toUtc();
    if (!assignment.leaseExpiresAt.toUtc().isAfter(now)) {
      return _reject(
        step: AssignmentValidationStep.contract,
        failureCode: 'LEASE_EXPIRED',
        retryable: true,
        detail: 'lease expired before execution',
      );
    }
    if (!assignment.startDeadlineAt.toUtc().isAfter(now)) {
      return _reject(
        step: AssignmentValidationStep.contract,
        failureCode: 'START_TIMEOUT',
        retryable: true,
        detail: 'start deadline elapsed',
      );
    }

    return const AssignmentReceiverVerdict.accept();
  }

  AssignmentReceiverVerdict validateFence({
    required WorkerAssignment assignment,
    int? checkpointFenceToken,
  }) {
    if (assignment.fenceToken < 1) {
      return _reject(
        step: AssignmentValidationStep.fence,
        failureCode: 'INPUT_SCHEMA_INVALID',
        retryable: false,
        detail: 'fenceToken must be >= 1',
      );
    }
    if (checkpointFenceToken != null && checkpointFenceToken != assignment.fenceToken) {
      return _reject(
        step: AssignmentValidationStep.fence,
        failureCode: 'POLICY_BLOCKED',
        retryable: false,
        detail: 'checkpoint fence $checkpointFenceToken does not match assignment fence ${assignment.fenceToken}',
      );
    }
    return const AssignmentReceiverVerdict.accept();
  }

  AssignmentReceiverVerdict validateConsent(DeviceSnapshot device) {
    for (final consent in ExecutionPolicy.requiredConsents) {
      if (!device.consentsGranted.contains(consent)) {
        return _reject(
          step: AssignmentValidationStep.consent,
          failureCode: 'CONSENT_MISMATCH',
          retryable: false,
          detail: 'missing consent: $consent',
        );
      }
    }
    return const AssignmentReceiverVerdict.accept();
  }

  void ensureAccepted(AssignmentReceiverVerdict verdict) {
    if (!verdict.accepted && verdict.issue != null) {
      throw AssignmentRejectedException(verdict.issue!);
    }
  }

  static bool _isSupportedTaskType(String taskType) {
    return TaskTypeMapper.toV1(taskType) != null || TaskTypeMapper.isPipelineTask(taskType);
  }

  static bool _isBlank(String value) => value.trim().isEmpty;

  static bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.hasAbsolutePath && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  static AssignmentReceiverVerdict _reject({
    required AssignmentValidationStep step,
    required String failureCode,
    required bool retryable,
    required String detail,
  }) {
    return AssignmentReceiverVerdict.rejected(
      AssignmentValidationIssue(
        step: step,
        failureCode: failureCode,
        retryable: retryable,
        detail: detail,
      ),
    );
  }
}
