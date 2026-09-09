import 'package:edgemint_worker/api/worker_assignment_models.dart';
import 'package:edgemint_worker/contracts/worker_error.dart';
import 'package:edgemint_worker/inference/llm/context_budget_manager.dart';
import 'package:edgemint_worker/runtime/device_constraints.dart';
import 'package:edgemint_worker/runtime/failure_evidence.dart';
import 'package:edgemint_worker/runtime/runtime_exceptions.dart';
import 'package:edgemint_worker/runtime/runtime_safety_controller.dart';
import 'package:edgemint_worker/runtime/worker_resource_budget.dart';
import 'package:edgemint_worker/runtime/worker_resource_enforcer.dart';
import 'package:flutter_test/flutter_test.dart';

WorkerAssignment _assignment() => WorkerAssignment(
      assignmentId: 'asg-123',
      attemptId: 'att-123',
      revisionId: 'rev-123',
      leaseToken: 'lease-token-1234567890',
      fenceToken: 4,
      leaseExpiresAt: DateTime.parse('2026-09-01T10:30:00Z'),
      taskType: 'text.summarize',
      modelVersionId: 'mdv-qwen',
      inputManifestUrl: 'https://example/input',
      outputUploadUrl: 'https://example/output',
      startDeadlineAt: DateTime.parse('2026-09-01T10:00:00Z'),
    );

void main() {
  const mapper = FailureEvidenceMapper();

  test('maps thermal safety abort to THERMAL_BLOCK', () {
    final evidence = mapper.map(
      assignment: _assignment(),
      error: RuntimeSafetyException(
        const RuntimeSafetyVerdict.abort(RuntimeSafetyReason.thermalCritical),
      ),
      executionTime: const Duration(seconds: 12),
    );

    expect(evidence, isNotNull);
    expect(evidence!.failureCode, ClosedFailureCode.thermalBlock);
    expect(evidence.retryable, isTrue);
    expect(evidence.fenceToken, 4);
    expect(evidence.metrics['executionTimeMs'], 12000);
  });

  test('maps memory pressure to RUNTIME_OUT_OF_MEMORY', () {
    final evidence = mapper.map(
      assignment: _assignment(),
      error: RuntimeSafetyException(
        const RuntimeSafetyVerdict.abort(RuntimeSafetyReason.memoryPressure),
      ),
      executionTime: const Duration(milliseconds: 64000),
      checkpointId: 'chk-45',
    );

    expect(evidence, isNotNull);
    expect(evidence!.failureCode, ClosedFailureCode.runtimeOutOfMemory);
    expect(evidence.retryable, isTrue);
    expect(evidence.checkpointId, 'chk-45');
  });

  test('maps runtime corruption to RUNTIME_CRASH', () {
    final evidence = mapper.map(
      assignment: _assignment(),
      error: RuntimeSafetyException(
        const RuntimeSafetyVerdict.abort(RuntimeSafetyReason.runtimeCorrupted),
      ),
      executionTime: Duration.zero,
    );

    expect(evidence?.failureCode, ClosedFailureCode.runtimeCrash);
    expect(evidence?.retryable, isTrue);
  });

  test('maps resource enforcer memory violation to INSUFFICIENT_MEMORY', () {
    final enforcer = WorkerResourceEnforcer(
      capacity: const DeviceResourceCapacity(
      cpuUnits: 1000,
      totalRamBytes: 4 * 1024 * 1024 * 1024,
      availableRamBytes: 2 * 1024 * 1024 * 1024,
      safetyReserveBytes: 512 * 1024 * 1024,
      storageAvailableBytes: 8 * 1024 * 1024 * 1024,
      storageMinimumFreeBytes: 512 * 1024 * 1024,
      maxAiStorageBytes: 2 * 1024 * 1024 * 1024,
    ),
  );
    final verdict = enforcer.evaluateRequest(
      reserved: const ResourceClassTotals(cpuUnits: 0, memoryBytes: 0, storageBytes: 0),
      requested: ResourceClassTotals(
        cpuUnits: 0,
        memoryBytes: enforcer.effectiveBudgets.memoryBytes + 1,
        storageBytes: 0,
      ),
    );

    final evidence = mapper.map(
      assignment: _assignment(),
      error: WorkerResourceEnforcementException(verdict),
      executionTime: const Duration(seconds: 1),
    );

    expect(evidence?.failureCode, ClosedFailureCode.insufficientMemory);
    expect(evidence?.retryable, isTrue);
  });

  test('maps worker OCR empty result to OCR_EMPTY_RESULT', () {
    final evidence = mapper.map(
      assignment: _assignment(),
      error: const WorkerError(
        code: WorkerErrorCode.ocrNoText,
        message: 'No text detected',
        retryable: true,
        stage: WorkerTaskStage.ocr,
      ),
      executionTime: const Duration(seconds: 3),
    );

    expect(evidence?.failureCode, ClosedFailureCode.ocrEmptyResult);
    expect(evidence?.retryable, isTrue);
  });

  test('maps context budget exception to CONTEXT_BUDGET_EXCEEDED', () {
    final evidence = mapper.map(
      assignment: _assignment(),
      error: ContextBudgetRequiresChunkException(
        const ContextBudgetEvaluation(
          route: ContextExecutionRoute.chunkPipeline,
          estimatedPromptTokens: 9000,
          estimatedSystemTokens: 128,
          estimatedTotalTokens: 9500,
          inputBudgetTokens: 8192,
        ),
      ),
      executionTime: const Duration(seconds: 2),
    );

    expect(evidence?.failureCode, ClosedFailureCode.contextBudgetExceeded);
    expect(evidence?.retryable, isTrue);
  });

  test('maps consent constraint to CONSENT_MISMATCH without retry', () {
    final evidence = mapper.map(
      assignment: _assignment(),
      error: ConstraintBlockedException(
        ConstraintViolation.missingConsent,
        'Missing consent: network',
      ),
      executionTime: Duration.zero,
    );

    expect(evidence?.failureCode, ClosedFailureCode.consentMismatch);
    expect(evidence?.retryable, isFalse);
  });

  test('toFailRequest uses closed errorCode and diagnostics envelope', () {
    final evidence = FailureEvidence(
      assignmentId: 'asg-123',
      attemptId: 'att-123',
      fenceToken: 4,
      failureCode: ClosedFailureCode.runtimeOutOfMemory,
      retryable: true,
      observedAt: DateTime.parse('2026-09-01T10:15:00Z'),
      metrics: {'executionTimeMs': 64000, 'peakMemoryBytes': 1835008000},
      checkpointId: 'chk-45',
    );

    final body = evidence.toFailRequest(leaseToken: 'lease-token-1234567890');
    expect(body['errorCode'], ClosedFailureCode.runtimeOutOfMemory);
    expect(body['retryable'], isTrue);
    expect(body['fenceToken'], 4);
    final diagnostics = body['diagnostics'] as Map<String, dynamic>;
    expect(diagnostics['checkpointId'], 'chk-45');
    expect(diagnostics['metrics'], isNotNull);
  });

  test('skips stale fence and lease revoked errors', () {
    expect(
      mapper.map(
        assignment: _assignment(),
        error: StaleFenceException(4, 3),
        executionTime: Duration.zero,
      ),
      isNull,
    );
    expect(
      mapper.map(
        assignment: _assignment(),
        error: const LeaseRevokedException(),
        executionTime: Duration.zero,
      ),
      isNull,
    );
  });
}
