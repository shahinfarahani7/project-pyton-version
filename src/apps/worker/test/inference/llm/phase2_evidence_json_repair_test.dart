// NOT RUN — requires Phase 2 compile flag:
// flutter test test/inference/llm/phase2_evidence_json_repair_test.dart
//   --dart-define=SUMMARIZE_EVIDENCE_V2=true

import 'dart:convert';

import 'package:edgemint_worker/contracts/worker_error.dart';
import 'package:edgemint_worker/inference/llm/prompt_templates.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/llm/summarize_evidence_pipeline.dart';
import 'package:edgemint_worker/inference/llm/summarize_inference_stage.dart';
import 'package:edgemint_worker/validation/json_output_validator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/phase2_evidence_chunk2.dart';

const _brokenEvidenceJson = 'not json at all';

const _incompleteRepairedEvidenceJson =
    '{"schemaVersion":"2","facts":["Order B426 had incorrect milk.","Refund is pen",'
    '"openItems":[],"priority":""}';

void main() {
  group('Phase 2 evidence JSON repair (NOT RUN by default)', () {
    test('accepts complete repaired evidence v2 without salvage', () async {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      var calls = 0;
      final logs = <String>[];
      final processor = QwenTaskProcessor(
        log: logs.add,
        runner: (prompt) async {
          calls += 1;
          if (prompt.contains('Fix the following broken JSON')) {
            return jsonEncode(phase2EvidenceChunk2);
          }
          return _brokenEvidenceJson;
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
      expect(result['schemaVersion'], '2');
      expect((result['facts'] as List), isNotEmpty);
      expect(result.containsKey('summary'), isFalse);
      expect(
        logs.any((line) => line.contains('[JSON CORRECTIVE] action=json_repair')),
        isTrue,
      );
      expect(
        logs.any((line) => line.contains('[JSON CORRECTIVE] action=labeled_fallback')),
        isFalse,
      );
      expect(logs.any((line) => line.contains('[MODEL COMPACT RETRY]')), isFalse);
      expect(logs.any((line) => line.contains('[JSON TRIMMED]')), isFalse);
    });

    test('rejects incomplete repaired evidence JSON without salvage', () async {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      var calls = 0;
      final logs = <String>[];
      final processor = QwenTaskProcessor(
        log: logs.add,
        runner: (prompt) async {
          calls += 1;
          if (prompt.contains('Fix the following broken JSON')) {
            return _incompleteRepairedEvidenceJson;
          }
          return _brokenEvidenceJson;
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
          inferenceStage: SummarizeInferenceStage.intermediateEvidence,
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
          _incompleteRepairedEvidenceJson,
          allowSalvage: true,
        ).ok,
        isTrue,
      );
      expect(
        JsonOutputValidator.extractJsonObject(
          _incompleteRepairedEvidenceJson,
          allowSalvage: false,
        ).ok,
        isFalse,
      );
      expect(logs.any((line) => line.contains('[JSON REPAIR FAILED]')), isTrue);
      expect(
        logs.where((line) => line.contains('[JSON CORRECTIVE]')).length,
        1,
      );
    });

    test('fails explicitly when shared corrective budget is exhausted', () async {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      var calls = 0;
      final logs = <String>[];
      final processor = QwenTaskProcessor(
        log: logs.add,
        runner: (prompt) async {
          calls += 1;
          return _brokenEvidenceJson;
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
          correctiveBudget: CorrectiveInferenceBudget(maxCalls: 0),
        ),
        throwsA(
          isA<WorkerError>()
              .having(
                (error) => error.code,
                'code',
                WorkerErrorCode.llmInvalidJson,
              )
              .having(
                (error) => error.message,
                'message',
                contains('corrective_budget_exhausted'),
              ),
        ),
      );

      expect(calls, 1);
      expect(
        logs.any((line) => line.contains('[JSON REPAIR SKIPPED] corrective budget exhausted')),
        isTrue,
      );
      expect(
        logs.any((line) => line.contains('[JSON CORRECTIVE] action=json_repair')),
        isFalse,
      );
    });
  });
}
