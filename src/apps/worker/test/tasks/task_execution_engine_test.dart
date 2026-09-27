import 'dart:convert';
import 'dart:typed_data';

import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/ocr/fake_ocr_engine.dart';
import 'package:edgemint_worker/runtime/execution_plan_runner.dart';
import 'package:edgemint_worker/runtime/inference_adapter.dart';
import 'package:edgemint_worker/runtime/model_runtime_manager.dart';
import 'package:edgemint_worker/tasks/task_execution_engine.dart';
import 'package:edgemint_worker/tasks/task_type_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:edgemint_worker/api/worker_assignment_models.dart';

import '../support/summarize_contract_mock_runner.dart';

void main() {
  group('TaskExecutionEngine', () {
    test('runs OCR-only pipeline with fake OCR engine', () async {
      final engine = TaskExecutionEngine(
        ocrEngine: FakeOcrEngine(),
        qwenProcessor: QwenTaskProcessor(
          runner: (_) async => '{"label":"invoice","confidence":0.9,"evidence":["x"]}',
        ),
      );
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      );
      final output = await engine.execute(
        context: TaskExecutionContext(
          assignment: WorkerAssignment(
            assignmentId: 'asg1',
            attemptId: 'att1',
            revisionId: 'rev1',
            leaseToken: 'lease',
            fenceToken: 1,
            leaseExpiresAt: DateTime.parse('2026-12-31T00:00:00Z'),
            taskType: 'document.ocr',
            modelVersionId: 'mdv_qwen3_0_6b',
            inputManifestUrl: 'http://example/manifest',
            outputUploadUrl: 'http://example/output',
            startDeadlineAt: DateTime.parse('2026-12-31T00:00:00Z'),
            taskId: 'tsk1',
          ),
          manifest: {
            'schemaVersion': '1.0',
            'idempotencyKey': 'key1',
            'options': {'minOcrConfidence': 0.5},
          },
          inputBytes: Uint8List.fromList(png),
          isImageInput: true,
        ),
        signingKey: 'sign',
        freeStorageMb: 8192,
      );
      expect(output.metrics['taskStatus'], 'succeeded');
      final result = engine.lastResult;
      expect(result?.output?['rawText'], isNotEmpty);
    });

    test('runs text.classify without OCR', () async {
      final engine = TaskExecutionEngine(
        ocrEngine: FakeOcrEngine(),
        qwenProcessor: QwenTaskProcessor(
          runner: (_) async => '{"label":"payment","confidence":0.88,"evidence":["code"]}',
        ),
      );
      final output = await engine.execute(
        context: TaskExecutionContext(
          assignment: WorkerAssignment(
            assignmentId: 'asg2',
            attemptId: 'att2',
            revisionId: 'rev2',
            leaseToken: 'lease',
            fenceToken: 1,
            leaseExpiresAt: DateTime.parse('2026-12-31T00:00:00Z'),
            taskType: 'text.classify',
            modelVersionId: 'mdv_qwen3_0_6b',
            inputManifestUrl: 'http://example/manifest',
            outputUploadUrl: 'http://example/output',
            startDeadlineAt: DateTime.parse('2026-12-31T00:00:00Z'),
            taskId: 'tsk2',
          ),
          manifest: {
            'schemaVersion': '1.0',
            'inputText': 'Your verification code is 123456',
            'options': {'allowedLabels': ['payment', 'other']},
          },
          inputBytes: Uint8List.fromList(utf8.encode('Your verification code is 123456')),
          isImageInput: false,
        ),
        signingKey: 'sign',
        freeStorageMb: 8192,
      );
      expect(output.metrics['taskStatus'], 'succeeded');
      expect(engine.lastResult?.output?['data']?['label'], 'payment');
    });

    test('clears execution plan binding after llm task completes', () async {
      final memory = InMemoryModelRuntimeManager(verifyArtifact: false);
      final runner = ExecutionPlanRunner(modelRuntime: memory);
      final engine = TaskExecutionEngine(
        ocrEngine: FakeOcrEngine(),
        qwenProcessor: QwenTaskProcessor(
          runner: (_) async => '{"label":"payment","confidence":0.88,"evidence":["code"]}',
        ),
        executionPlanRunner: runner,
      );
      await engine.execute(
        context: TaskExecutionContext(
          assignment: WorkerAssignment(
            assignmentId: 'asg3',
            attemptId: 'att3',
            revisionId: 'rev3',
            leaseToken: 'lease',
            fenceToken: 4,
            leaseExpiresAt: DateTime.parse('2026-12-31T00:00:00Z'),
            taskType: 'text.classify',
            modelVersionId: 'mdv_qwen3_0_6b',
            inputManifestUrl: 'http://example/manifest',
            outputUploadUrl: 'http://example/output',
            startDeadlineAt: DateTime.parse('2026-12-31T00:00:00Z'),
            taskId: 'tsk3',
          ),
          manifest: {
            'schemaVersion': '1.0',
            'inputText': 'Your verification code is 123456',
            'options': {'allowedLabels': ['payment', 'other']},
          },
          inputBytes: Uint8List.fromList(utf8.encode('Your verification code is 123456')),
          isImageInput: false,
        ),
        signingKey: 'sign',
        freeStorageMb: 8192,
      );
      expect(runner.boundAssignmentId, isNull);
      expect(memory.openSessionCount, 0);
    });

    test('injected plan runner executes map-reduce shell for text.summarize', () async {
      final memory = InMemoryModelRuntimeManager(verifyArtifact: false);
      await memory.ensureResident(
        artifact: ModelArtifact(
          modelVersionId: 'mdv_qwen2_5_0_5b',
          digestSha256: 'digest',
          signatureSha256: 'sig',
          backend: InferenceBackend.liteRt,
          bytes: Uint8List.fromList([1]),
        ),
        signingKey: 'sign',
      );
      final runner = ExecutionPlanRunner(modelRuntime: memory);
      final engine = TaskExecutionEngine(
        ocrEngine: FakeOcrEngine(),
        qwenProcessor: QwenTaskProcessor(runner: summarizeContractMockRunner),
        executionPlanRunner: runner,
      );
      final longText = List.filled(12, 'Paragraph one with enough tokens for chunking.').join('\n\n');

      final output = await engine.execute(
        context: TaskExecutionContext(
          assignment: WorkerAssignment(
            assignmentId: 'asg-summarize-plan',
            attemptId: 'att-summarize-plan',
            revisionId: 'rev-summarize-plan',
            leaseToken: 'lease',
            fenceToken: 11,
            leaseExpiresAt: DateTime.parse('2026-12-31T00:00:00Z'),
            taskType: 'text.summarize',
            modelVersionId: 'mdv_qwen2_5_0_5b',
            inputManifestUrl: 'http://example/manifest',
            outputUploadUrl: 'http://example/output',
            startDeadlineAt: DateTime.parse('2026-12-31T00:00:00Z'),
            taskId: 'tsk-summarize-plan',
          ),
          manifest: {
            'schemaVersion': '1.0',
            'inputText': longText,
            'options': {'maxBullets': 5},
          },
          inputBytes: Uint8List.fromList(utf8.encode(longText)),
          isImageInput: false,
        ),
        signingKey: 'sign',
        freeStorageMb: 8192,
      );

      expect(output.metrics['taskStatus'], 'succeeded');
      expect(runner.boundAssignmentId, isNull);
      expect(memory.sessionCount, greaterThan(0));
      expect(memory.openSessionCount, 0);
    });

    test('production LLM path selects map-reduce catalog plan for summarize', () {
      final processor = QwenTaskProcessor();
      expect(processor.requiresNativeRuntime, isTrue);
      final plan = ExecutionPlanCatalog.forTaskType(TaskTypeMapper.textSummarize);
      expect(
        plan.stages.map((stage) => stage.operation),
        containsAll(['chunk', 'llm_map', 'llm_reduce']),
      );
    });

    test('mock LLM without injected runner bypasses plan shell for summarize', () async {
      final memory = InMemoryModelRuntimeManager(verifyArtifact: false);
      await memory.ensureResident(
        artifact: ModelArtifact(
          modelVersionId: 'mdv_qwen2_5_0_5b',
          digestSha256: 'digest',
          signatureSha256: 'sig',
          backend: InferenceBackend.liteRt,
          bytes: Uint8List.fromList([1]),
        ),
        signingKey: 'sign',
      );
      final runner = ExecutionPlanRunner(modelRuntime: memory);
      final engine = TaskExecutionEngine(
        ocrEngine: FakeOcrEngine(),
        qwenProcessor: QwenTaskProcessor(runner: summarizeContractMockRunner),
      );
      final longText = List.filled(12, 'Paragraph one with enough tokens for chunking.').join('\n\n');

      final output = await engine.execute(
        context: TaskExecutionContext(
          assignment: WorkerAssignment(
            assignmentId: 'asg-direct-summarize',
            attemptId: 'att-direct',
            revisionId: 'rev-direct',
            leaseToken: 'lease',
            fenceToken: 12,
            leaseExpiresAt: DateTime.parse('2026-12-31T00:00:00Z'),
            taskType: 'text.summarize',
            modelVersionId: 'mdv_qwen2_5_0_5b',
            inputManifestUrl: 'http://example/manifest',
            outputUploadUrl: 'http://example/output',
            startDeadlineAt: DateTime.parse('2026-12-31T00:00:00Z'),
            taskId: 'tsk-direct',
          ),
          manifest: {
            'schemaVersion': '1.0',
            'inputText': longText,
          },
          inputBytes: Uint8List.fromList(utf8.encode(longText)),
          isImageInput: false,
        ),
        signingKey: 'sign',
        freeStorageMb: 8192,
      );

      expect(output.metrics['taskStatus'], 'succeeded');
      expect(runner.boundAssignmentId, isNull);
      expect(memory.sessionCount, 0);
    });

    test('injected plan runner releases binding after summarize validation failure', () async {
      final memory = InMemoryModelRuntimeManager(verifyArtifact: false);
      await memory.ensureResident(
        artifact: ModelArtifact(
          modelVersionId: 'mdv_qwen2_5_0_5b',
          digestSha256: 'digest',
          signatureSha256: 'sig',
          backend: InferenceBackend.liteRt,
          bytes: Uint8List.fromList([1]),
        ),
        signingKey: 'sign',
      );
      final runner = ExecutionPlanRunner(modelRuntime: memory);
      final engine = TaskExecutionEngine(
        ocrEngine: FakeOcrEngine(),
        qwenProcessor: QwenTaskProcessor(
          runner: (_) async => '{"summary":"bad","bullets":["x"]}',
        ),
        executionPlanRunner: runner,
      );
      final longText = List.filled(12, 'Paragraph one with enough tokens for chunking.').join('\n\n');

      final output = await engine.execute(
        context: TaskExecutionContext(
          assignment: WorkerAssignment(
            assignmentId: 'asg-summarize-fail',
            attemptId: 'att-fail',
            revisionId: 'rev-fail',
            leaseToken: 'lease',
            fenceToken: 13,
            leaseExpiresAt: DateTime.parse('2026-12-31T00:00:00Z'),
            taskType: 'text.summarize',
            modelVersionId: 'mdv_qwen2_5_0_5b',
            inputManifestUrl: 'http://example/manifest',
            outputUploadUrl: 'http://example/output',
            startDeadlineAt: DateTime.parse('2026-12-31T00:00:00Z'),
            taskId: 'tsk-fail',
          ),
          manifest: {
            'schemaVersion': '1.0',
            'inputText': longText,
          },
          inputBytes: Uint8List.fromList(utf8.encode(longText)),
          isImageInput: false,
        ),
        signingKey: 'sign',
        freeStorageMb: 8192,
      );

      expect(output.metrics['taskStatus'], 'retryable');
      expect(runner.boundAssignmentId, isNull);
      expect(memory.openSessionCount, 0);
    });
  });
}
