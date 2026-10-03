import '../api/worker_assignment_models.dart';
import '../contracts/worker_error.dart';
import '../inference/llm/context_budget_manager.dart';
import '../inference/llm/hierarchical_reduce_bounds.dart';
import '../inference/llm/semantic_merge_validator.dart';
import 'network_transport.dart';
import 'resume_grant.dart';
import 'assignment_receiver.dart';
import 'device_constraints.dart';
import 'runtime_exceptions.dart';
import 'runtime_safety_controller.dart';
import 'worker_resource_enforcer.dart';

/// Closed worker failure codes (Architecture Section 41 + Section 43).
abstract final class ClosedFailureCode {
  static const modelUnavailable = 'MODEL_UNAVAILABLE';
  static const insufficientMemory = 'INSUFFICIENT_MEMORY';
  static const insufficientStorage = 'INSUFFICIENT_STORAGE';
  static const runtimeIncompatible = 'RUNTIME_INCOMPATIBLE';
  static const thermalBlock = 'THERMAL_BLOCK';
  static const networkPolicyMismatch = 'NETWORK_POLICY_MISMATCH';
  static const deliveryTimeout = 'DELIVERY_TIMEOUT';
  static const startTimeout = 'START_TIMEOUT';
  static const consentMismatch = 'CONSENT_MISMATCH';
  static const runtimeOutOfMemory = 'RUNTIME_OUT_OF_MEMORY';
  static const runtimeCrash = 'RUNTIME_CRASH';
  static const inferenceTimeout = 'INFERENCE_TIMEOUT';
  static const modelExecutionFailed = 'MODEL_EXECUTION_FAILED';
  static const osProcessTerminated = 'OS_PROCESS_TERMINATED';
  static const inputRuntimeUnsupported = 'INPUT_RUNTIME_UNSUPPORTED';
  static const inputFetchTimeout = 'INPUT_FETCH_TIMEOUT';
  static const inputUnavailable = 'INPUT_UNAVAILABLE';
  static const longFormIncomplete = 'LONG_FORM_INCOMPLETE';
  static const contextBudgetExceeded = 'CONTEXT_BUDGET_EXCEEDED';
  static const checkpointIncompatible = 'CHECKPOINT_INCOMPATIBLE';
  static const resultInvalidJson = 'RESULT_INVALID_JSON';
  static const resultSchemaMismatch = 'RESULT_SCHEMA_MISMATCH';
  static const resultEmpty = 'RESULT_EMPTY';
  static const resultLowConfidence = 'RESULT_LOW_CONFIDENCE';
  static const resultSignatureInvalid = 'RESULT_SIGNATURE_INVALID';
  static const goldenValidationFailed = 'GOLDEN_VALIDATION_FAILED';
  static const resourcePressure = 'RESOURCE_PRESSURE';
  static const workerDisconnected = 'WORKER_DISCONNECTED';
  static const networkUnavailable = 'NETWORK_UNAVAILABLE';
  static const leaseExpired = 'LEASE_EXPIRED';
  static const resultValidationFailed = 'RESULT_VALIDATION_FAILED';
  static const ocrEmptyResult = 'OCR_EMPTY_RESULT';
  static const visionLowConfidence = 'VISION_LOW_CONFIDENCE';
  static const inputSchemaInvalid = 'INPUT_SCHEMA_INVALID';
  static const permissionDenied = 'PERMISSION_DENIED';
  static const consentRevoked = 'CONSENT_REVOKED';
  static const policyBlocked = 'POLICY_BLOCKED';
  static const unrecoverableFile = 'UNRECOVERABLE_FILE';
  static const taskCancelled = 'TASK_CANCELLED';
  static const deadlineExpired = 'DEADLINE_EXPIRED';
}

class FailureEvidence {
  const FailureEvidence({
    required this.assignmentId,
    required this.attemptId,
    required this.fenceToken,
    required this.failureCode,
    required this.retryable,
    required this.observedAt,
    this.metrics = const {},
    this.checkpointId,
    this.healthSnapshotSequence,
  });

  final String assignmentId;
  final String attemptId;
  final int fenceToken;
  final String failureCode;
  final bool retryable;
  final DateTime observedAt;
  final Map<String, dynamic> metrics;
  final String? checkpointId;
  final int? healthSnapshotSequence;

  Map<String, dynamic> toFailRequest({required String leaseToken}) {
    final diagnostics = <String, dynamic>{
      'assignmentId': assignmentId,
      'attemptId': attemptId,
      'observedAt': observedAt.toUtc().toIso8601String(),
      if (metrics.isNotEmpty) 'metrics': metrics,
      if (checkpointId != null) 'checkpointId': checkpointId,
      if (healthSnapshotSequence != null) 'healthSnapshotSequence': healthSnapshotSequence,
    };
    return {
      'leaseToken': leaseToken,
      'fenceToken': fenceToken,
      'errorCode': failureCode,
      'retryable': retryable,
      'diagnostics': diagnostics,
    };
  }
}

/// Maps local worker exceptions to closed architecture failure codes.
class FailureEvidenceMapper {
  const FailureEvidenceMapper();

  FailureEvidence? map({
    required WorkerAssignment assignment,
    required Object error,
    required Duration executionTime,
    String? checkpointId,
    int? healthSnapshotSequence,
    Map<String, dynamic>? extraMetrics,
  }) {
    final mapped = _mapCodeAndRetry(error);
    if (mapped == null) {
      return null;
    }
    final metrics = <String, dynamic>{
      'executionTimeMs': executionTime.inMilliseconds,
      if (extraMetrics != null) ...extraMetrics,
    };
    return FailureEvidence(
      assignmentId: assignment.assignmentId,
      attemptId: assignment.attemptId,
      fenceToken: assignment.fenceToken,
      failureCode: mapped.code,
      retryable: mapped.retryable,
      observedAt: DateTime.now().toUtc(),
      metrics: metrics,
      checkpointId: checkpointId,
      healthSnapshotSequence: healthSnapshotSequence,
    );
  }

  _MappedFailure? _mapCodeAndRetry(Object error) {
    if (NetworkFailure.isTransport(error)) {
      return const _MappedFailure(ClosedFailureCode.networkUnavailable, true);
    }
    if (error is RuntimeSafetyException) {
      return switch (error.verdict.reason) {
        RuntimeSafetyReason.thermalCritical ||
        RuntimeSafetyReason.thermalThrottled =>
          const _MappedFailure(ClosedFailureCode.thermalBlock, true),
        RuntimeSafetyReason.memoryPressure =>
          const _MappedFailure(ClosedFailureCode.runtimeOutOfMemory, true),
        RuntimeSafetyReason.osPressure =>
          const _MappedFailure(ClosedFailureCode.resourcePressure, true),
        RuntimeSafetyReason.runtimeCorrupted =>
          const _MappedFailure(ClosedFailureCode.runtimeCrash, true),
        null => const _MappedFailure(ClosedFailureCode.runtimeCrash, true),
      };
    }
    if (error is ConstraintBlockedException) {
      return switch (error.violation) {
        ConstraintViolation.thermalCritical =>
          const _MappedFailure(ClosedFailureCode.thermalBlock, true),
        ConstraintViolation.storageLow =>
          const _MappedFailure(ClosedFailureCode.insufficientStorage, true),
        ConstraintViolation.missingConsent =>
          const _MappedFailure(ClosedFailureCode.consentMismatch, false),
        ConstraintViolation.networkOffline =>
          const _MappedFailure(ClosedFailureCode.networkPolicyMismatch, false),
        ConstraintViolation.batteryLow ||
        ConstraintViolation.unavailable =>
          const _MappedFailure(ClosedFailureCode.resourcePressure, true),
        ConstraintViolation.scheduleBlocked =>
          const _MappedFailure(ClosedFailureCode.policyBlocked, false),
        null => const _MappedFailure(ClosedFailureCode.policyBlocked, false),
      };
    }
    if (error is WorkerResourceEnforcementException) {
      return switch (error.verdict.violation) {
        ResourceBudgetViolation.memoryBudgetExceeded =>
          const _MappedFailure(ClosedFailureCode.insufficientMemory, true),
        ResourceBudgetViolation.storageBudgetExceeded =>
          const _MappedFailure(ClosedFailureCode.insufficientStorage, true),
        ResourceBudgetViolation.cpuBudgetExceeded =>
          const _MappedFailure(ClosedFailureCode.resourcePressure, true),
        null => const _MappedFailure(ClosedFailureCode.resourcePressure, true),
      };
    }
    if (error is ContextBudgetRequiresChunkException) {
      return const _MappedFailure(ClosedFailureCode.contextBudgetExceeded, true);
    }
    if (error is HierarchicalReduceExhaustedException) {
      return const _MappedFailure(ClosedFailureCode.contextBudgetExceeded, true);
    }
    if (error is SemanticMergeNoProgressException) {
      return const _MappedFailure(ClosedFailureCode.contextBudgetExceeded, true);
    }
    if (error is ResumeGrantRejectedException) {
      return const _MappedFailure(ClosedFailureCode.checkpointIncompatible, true);
    }
    if (error is ModelIntegrityException) {
      return const _MappedFailure(ClosedFailureCode.modelExecutionFailed, true);
    }
    if (error is WorkerError) {
      return switch (error.code) {
        WorkerErrorCode.modelNotAvailable =>
          const _MappedFailure(ClosedFailureCode.modelUnavailable, true),
        WorkerErrorCode.outOfMemoryRisk =>
          const _MappedFailure(ClosedFailureCode.runtimeOutOfMemory, true),
        WorkerErrorCode.cancelled =>
          const _MappedFailure(ClosedFailureCode.taskCancelled, false),
        WorkerErrorCode.deadlineExceeded =>
          const _MappedFailure(ClosedFailureCode.deadlineExpired, false),
        WorkerErrorCode.llmInvalidJson =>
          const _MappedFailure(ClosedFailureCode.resultInvalidJson, false),
        WorkerErrorCode.outputSchemaMismatch =>
          const _MappedFailure(ClosedFailureCode.resultSchemaMismatch, false),
        WorkerErrorCode.longFormIncomplete =>
          const _MappedFailure(ClosedFailureCode.longFormIncomplete, false),
        WorkerErrorCode.ocrNoText =>
          const _MappedFailure(ClosedFailureCode.ocrEmptyResult, true),
        WorkerErrorCode.ocrLowConfidence =>
          const _MappedFailure(ClosedFailureCode.resultLowConfidence, true),
        WorkerErrorCode.unsupportedTaskType ||
        WorkerErrorCode.invalidTask =>
          const _MappedFailure(ClosedFailureCode.inputSchemaInvalid, false),
        WorkerErrorCode.imageTooLarge ||
        WorkerErrorCode.imageDecodeFailed =>
          const _MappedFailure(ClosedFailureCode.inputRuntimeUnsupported, false),
        WorkerErrorCode.visionRuntimeNotReady =>
          const _MappedFailure(ClosedFailureCode.modelUnavailable, true),
        WorkerErrorCode.internalError =>
          const _MappedFailure(ClosedFailureCode.runtimeCrash, true),
      };
    }
    if (error is InputFetchException) {
      return _MappedFailure(
        error.timedOut
            ? ClosedFailureCode.inputFetchTimeout
            : ClosedFailureCode.inputUnavailable,
        true,
      );
    }
    if (error is AssignmentRejectedException) {
      return _MappedFailure(error.failureCode, error.retryable);
    }
    if (error is LeaseRevokedException || error is StaleFenceException) {
      return null;
    }
    if (error is StateError) {
      final message = error.message.toLowerCase();
      if (message.contains('sandbox time limit') || message.contains('timeout')) {
        return const _MappedFailure(ClosedFailureCode.inferenceTimeout, true);
      }
      return const _MappedFailure(ClosedFailureCode.runtimeCrash, true);
    }
    return const _MappedFailure(ClosedFailureCode.runtimeCrash, true);
  }
}

class _MappedFailure {
  const _MappedFailure(this.code, this.retryable);

  final String code;
  final bool retryable;
}
