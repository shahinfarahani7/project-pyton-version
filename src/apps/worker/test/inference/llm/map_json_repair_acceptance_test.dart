import 'dart:convert';

import 'package:edgemint_worker/contracts/worker_error.dart';
import 'package:edgemint_worker/inference/llm/prompt_templates.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/llm/summarize_inference_stage.dart';
import 'package:edgemint_worker/validation/json_output_validator.dart';
import 'package:flutter_test/flutter_test.dart';

const _completeMapJson = {
  'summary': 'Chunk facts recovered.',
  'keyPoints': ['Order B426 had incorrect milk.', 'Refund is pending.'],
  'mainComplaint': '',
  'suggestedImprovement': '',
  'missingOrUnclear': ['Refund timing unclear.'],
};

const _incompleteRepairedJson =
    '{"summary":"Chunk facts recovered.",'
    '"keyPoints":["Order B426 had incorrect milk.","Refund is pen",'
    '"mainComplaint":"","suggestedImprovement":"","missingOrUnclear":[]}';

const _brokenMapJson = 'not json at all';

void main() {
  group('Map JSON repair strict completeness', () {
    test('accepts complete repaired Map JSON without salvage', () async {
      var calls = 0;
      final logs = <String>[];
      final processor = QwenTaskProcessor(
        log: logs.add,
        runner: (prompt) async {
          calls += 1;
          if (prompt.contains('Fix the following broken JSON')) {
            return jsonEncode(_completeMapJson);
          }
          return _brokenMapJson;
        },
      );

      final result = await processor.runJsonTask(
        prompt: PromptTemplates.summarizeMapChunk(
          chunkText: 'Order B426 had incorrect milk.',
          chunkIndex: 0,
          totalChunks: 2,
          chunkId: 'c' * 64,
        ),
        inferenceStage: SummarizeInferenceStage.mapEvidence,
        signingKey: 'sign',
        labeledFallback: false,
        correctiveBudget: CorrectiveInferenceBudget(maxCalls: 1),
      );

      expect(calls, 2);
      expect(result['summary'], _completeMapJson['summary']);
      expect(
        logs.any((line) => line.contains('[JSON CORRECTIVE] action=json_repair')),
        isTrue,
      );
      expect(
        logs.any((line) => line.contains('[JSON CORRECTIVE] action=labeled_fallback')),
        isFalse,
      );
      expect(logs.any((line) => line.contains('[MODEL COMPACT RETRY]')), isFalse);
    });

    test('rejects incomplete repaired Map JSON without salvage or completion',
        () async {
      var calls = 0;
      final logs = <String>[];
      final processor = QwenTaskProcessor(
        log: logs.add,
        runner: (prompt) async {
          calls += 1;
          if (prompt.contains('Fix the following broken JSON')) {
            return _incompleteRepairedJson;
          }
          return _brokenMapJson;
        },
      );

      await expectLater(
        processor.runJsonTask(
          prompt: PromptTemplates.summarizeMapChunk(
            chunkText: 'Order B426 had incorrect milk.',
            chunkIndex: 0,
            totalChunks: 2,
            chunkId: 'c' * 64,
          ),
          inferenceStage: SummarizeInferenceStage.mapEvidence,
        signingKey: 'sign',
          labeledFallback: false,
          correctiveBudget: CorrectiveInferenceBudget(maxCalls: 1),
        ),
        throwsA(
          isA<WorkerError>().having(
            (error) => error.code,
            'code',
            WorkerErrorCode.llmInvalidJson,
          ),
        ),
      );

      expect(calls, 2);
      expect(
        JsonOutputValidator.extractJsonObject(
          _incompleteRepairedJson,
          allowSalvage: true,
        ).ok,
        isTrue,
        reason: 'salvage-enabled control must still salvage this payload',
      );
      expect(
        JsonOutputValidator.extractJsonObject(
          _incompleteRepairedJson,
          allowSalvage: false,
        ).ok,
        isFalse,
      );
      expect(logs.any((line) => line.contains('[JSON REPAIR FAILED]')), isTrue);
      expect(logs.any((line) => line.contains('[MODEL COMPACT RETRY]')), isFalse);
      expect(
        logs.where((line) => line.contains('[JSON CORRECTIVE]')).length,
        1,
      );
    });

    test('does not spend a second corrective call after failed repair', () async {
      var calls = 0;
      final processor = QwenTaskProcessor(
        runner: (prompt) async {
          calls += 1;
          if (prompt.contains('Fix the following broken JSON')) {
            return _incompleteRepairedJson;
          }
          return _brokenMapJson;
        },
      );

      await expectLater(
        processor.runJsonTask(
          prompt: PromptTemplates.summarizeMapChunk(
            chunkText: 'Order B426 had incorrect milk.',
            chunkIndex: 0,
            totalChunks: 2,
            chunkId: 'c' * 64,
          ),
          inferenceStage: SummarizeInferenceStage.mapEvidence,
        signingKey: 'sign',
          labeledFallback: false,
          correctiveBudget: CorrectiveInferenceBudget(maxCalls: 1),
        ),
        throwsA(isA<WorkerError>()),
      );

      expect(calls, 2);
    });
  });
}
