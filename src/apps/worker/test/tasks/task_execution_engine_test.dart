import 'dart:convert';
import 'dart:typed_data';

import 'package:edgemint_worker/contracts/worker_task_request.dart';
import 'package:edgemint_worker/contracts/worker_task_result.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/ocr/fake_ocr_engine.dart';
import 'package:edgemint_worker/tasks/task_execution_engine.dart';
import 'package:edgemint_worker/tasks/task_type_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:edgemint_worker/api/worker_assignment_models.dart';

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
  });
}
