import 'dart:convert';
import 'dart:typed_data';

import 'package:edgemint_worker/api/worker_assignment_models.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/ocr/fake_ocr_engine.dart';
import 'package:edgemint_worker/runtime/execution_plan_runner.dart';
import 'package:edgemint_worker/runtime/model_runtime_manager.dart';
import 'package:edgemint_worker/tasks/task_execution_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Automated Phase 3 integration smoke: OCR + Qwen paths through ExecutionPlanRunner shell.
void main() {
  group('Phase 3 integration smoke', () {
    late InMemoryModelRuntimeManager modelRuntime;
    late ExecutionPlanRunner planRunner;
    late TaskExecutionEngine engine;

    setUp(() {
      modelRuntime = InMemoryModelRuntimeManager(verifyArtifact: false);
      planRunner = ExecutionPlanRunner(modelRuntime: modelRuntime);
      engine = TaskExecutionEngine(
        ocrEngine: FakeOcrEngine(),
        qwenProcessor: QwenTaskProcessor(
          runner: (_) async => '{"summary":"Smoke summary.","bullets":["a","b"]}',
        ),
        executionPlanRunner: planRunner,
      );
    });

    test('document.ocr completes through runtime shell with OCR stage', () async {
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      );

      final output = await engine.execute(
        context: TaskExecutionContext(
          assignment: _assignment(taskType: 'document.ocr', assignmentId: 'asg_ocr_smoke'),
          manifest: {
            'schemaVersion': '1.0',
            'idempotencyKey': 'ocr-smoke',
            'options': {'minOcrConfidence': 0.5},
          },
          inputBytes: Uint8List.fromList(png),
          isImageInput: true,
        ),
        signingKey: 'sign',
        freeStorageMb: 8192,
      );

      expect(output.metrics['taskStatus'], 'succeeded');
      expect(engine.lastResult?.output?['rawText'], isNotEmpty);
      expect(planRunner.boundAssignmentId, isNull);
      expect(modelRuntime.openSessionCount, 0);
    });

    test('text.summarize completes through ExecutionPlanRunner map-reduce shell', () async {
      final longText = List.filled(12, 'Paragraph one with enough tokens for chunking.').join('\n\n');

      final output = await engine.execute(
        context: TaskExecutionContext(
          assignment: _assignment(taskType: 'text.summarize', assignmentId: 'asg_qwen_smoke'),
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
      expect(engine.lastResult?.output?['summary'], isNotEmpty);
      expect(planRunner.boundAssignmentId, isNull);
      expect(modelRuntime.sessionCount, greaterThan(0));
      expect(modelRuntime.openSessionCount, 0);
    });
  });
}

WorkerAssignment _assignment({
  required String taskType,
  required String assignmentId,
}) {
  return WorkerAssignment(
    assignmentId: assignmentId,
    attemptId: 'att_$assignmentId',
    revisionId: 'rev_$assignmentId',
    leaseToken: 'lease_$assignmentId',
    fenceToken: 7,
    leaseExpiresAt: DateTime.parse('2026-12-31T00:00:00Z'),
    taskType: taskType,
    modelVersionId: 'mdv_qwen2_5_0_5b',
    inputManifestUrl: 'http://example/manifest',
    outputUploadUrl: 'http://example/output',
    startDeadlineAt: DateTime.parse('2026-12-31T00:00:00Z'),
    taskId: 'tsk_$assignmentId',
  );
}
