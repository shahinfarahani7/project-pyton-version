import 'dart:convert';

import 'package:edgemint_worker/contracts/worker_error.dart';
import 'package:edgemint_worker/inference/llm/prompt_templates.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/llm/summarize_evidence_pipeline.dart';
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
  // V1 map partial repair (five-field JSON). Under SUMMARIZE_EVIDENCE_V2=true, mapEvidence
  // uses evidence v2 schema; repair/incomplete cases live in
  // phase2_evidence_json_repair_test.dart.
  group('Map JSON repair strict completeness (v1 five-field map partial only)', () {
    test('accepts complete repaired Map JSON without salvage', () async {
      if (SummarizeEvidencePipeline.enabled) {
        return;
      }
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
      if (SummarizeEvidencePipeline.enabled) {
        return;
      }
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
      if (SummarizeEvidencePipeline.enabled) {
        return;
      }
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

  group('Map JSON repair at mapEvidence when evidence v2 is active', () {
    test('rejects legacy five-field model output without json_repair success',
        () async {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      var calls = 0;
      final processor = QwenTaskProcessor(
        runner: (prompt) async {
          calls += 1;
          return jsonEncode(_completeMapJson);
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
          correctiveBudget: CorrectiveInferenceBudget(maxCalls: 0),
        ),
        throwsA(
          isA<WorkerError>().having(
            (error) => error.code,
            'code',
            WorkerErrorCode.outputSchemaMismatch,
          ),
        ),
      );
      expect(calls, 1);
    });
  });
}
