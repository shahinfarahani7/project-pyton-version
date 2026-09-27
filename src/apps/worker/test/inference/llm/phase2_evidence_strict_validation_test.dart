// NOT RUN — requires Phase 2 compile flag:
// flutter test test/inference/llm/phase2_evidence_strict_validation_test.dart
//   --dart-define=SUMMARIZE_EVIDENCE_V2=true

import 'dart:convert';

import 'package:edgemint_worker/contracts/worker_error.dart';
import 'package:edgemint_worker/inference/llm/evidence_partial_validator.dart';
import 'package:edgemint_worker/inference/llm/prompt_templates.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/llm/summarize_constraint_renderer.dart';
import 'package:edgemint_worker/inference/llm/summarize_evidence_pipeline.dart';
import 'package:edgemint_worker/inference/llm/summarize_evidence_schema.dart';
import 'package:edgemint_worker/inference/llm/summarize_inference_stage.dart';
import 'package:edgemint_worker/inference/llm/summarize_task_constraints.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/phase2_evidence_chunk2.dart';
import 'fixtures/summarize_v2_prompt_matchers.dart';
import 'fixtures/task_28f6542b_map1_reconstructed.dart';

const _brokenJson = 'not json at all';

void main() {
  group('Phase 2 evidence strict validation (NOT RUN by default)', () {
    test('A rejects object facts before normalize would drop them', () {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      final normalizedWouldEmpty = SummarizeEvidenceSchema.validateStructure(
        task28f6542bMap1ObjectFactsReconstructed,
      );
      expect(normalizedWouldEmpty, isNotNull);
      expect(
        normalizedWouldEmpty,
        allOf(
          contains('evidence_facts_invalid_element:index=0:type='),
          contains('Map'),
        ),
      );
    });

    test('A runJsonTask rejects object facts before checkpoint path', () async {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      final logs = <String>[];
      final processor = QwenTaskProcessor(
        log: logs.add,
        runner: (prompt) async =>
            jsonEncode(task28f6542bMap1ObjectFactsReconstructed),
      );

      await expectLater(
        processor.runJsonTask(
          prompt: PromptTemplates.summarizeMapChunk(
            chunkText: 'Order B410 and B426 issues.',
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
            WorkerErrorCode.outputSchemaMismatch,
          ),
        ),
      );

      expect(
        logs.any(
          (line) => line.contains(
            '[EVIDENCE SCHEMA REJECTED] reason=evidence_facts_invalid_element:index=0:type=_Map',
          ),
        ),
        isTrue,
      );
      expect(
        logs.any((line) => line.contains('[JSON CORRECTIVE] action=json_repair')),
        isFalse,
      );
    });

    test('B rejects mixed string/object facts arrays', () {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      final reason = SummarizeEvidenceSchema.validateStructure({
        'schemaVersion': '2',
        'facts': ['valid fact', {'bad': 'object'}],
        'openItems': [],
        'priority': '',
      });
      expect(reason, contains('evidence_facts_invalid_element:index=1:type='));
    });

    test('C rejects wrong member types in openItems', () {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      final reason = SummarizeEvidenceSchema.validateStructure({
        'schemaVersion': '2',
        'facts': [],
        'openItems': [42],
        'priority': '',
      });
      expect(
        reason,
        contains('evidence_open_items_invalid_element:index=0:type=int'),
      );
    });

    test('D supports legitimate explicit empty facts', () {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      expect(SummarizeEvidenceSchema.isEmptyPartial(phase2EvidenceAllEmpty), isTrue);
      final issues = EvidencePartialValidator.validate(
        partial: phase2EvidenceOpenItemsOnly,
        generationTruncated: false,
      );
      expect(issues, isEmpty);
    });

    test('E invalid evidence cannot pass checkpoint validation', () {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      final issues = EvidencePartialValidator.validate(
        partial: task28f6542bMap1ObjectFactsReconstructed,
        generationTruncated: false,
      );
      expect(issues, isNotEmpty);
      expect(issues.first, contains('evidence_facts_invalid_element'));
    });

    test('F truncated initial evidence performs no corrective inference', () async {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      var calls = 0;
      final logs = <String>[];
      final processor = QwenTaskProcessor(
        log: logs.add,
        testRunnerTruncated: true,
        testRunnerStopReason: 'output_limit',
        runner: (prompt) async {
          calls += 1;
          return _brokenJson;
        },
      );

      await expectLater(
        processor.runJsonTask(
          prompt: PromptTemplates.summarizeMapChunk(
            chunkText: 'Chunk body.',
            chunkIndex: 1,
            totalChunks: 2,
            chunkId: 'd' * 64,
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
            WorkerErrorCode.outputSchemaMismatch,
          ),
        ),
      );

      expect(calls, 1);
      expect(
        logs.any((line) => line.contains('[EVIDENCE GENERATION TRUNCATED]')),
        isTrue,
      );
      expect(
        logs.any((line) => line.contains('[JSON CORRECTIVE] action=json_repair')),
        isFalse,
      );
    });

    test('G rejects truncated evidence even when JSON is syntactically valid',
        () async {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      final logs = <String>[];
      final processor = QwenTaskProcessor(
        log: logs.add,
        testRunnerTruncated: true,
        testRunnerStopReason: 'output_limit',
        runner: (prompt) async => jsonEncode(phase2EvidenceChunk2),
      );

      await expectLater(
        processor.runJsonTask(
          prompt: PromptTemplates.summarizeMapChunk(
            chunkText: 'Chunk body.',
            chunkIndex: 1,
            totalChunks: 2,
            chunkId: 'd' * 64,
          ),
          inferenceStage: SummarizeInferenceStage.intermediateEvidence,
          signingKey: 'sign',
          labeledFallback: false,
          correctiveBudget: CorrectiveInferenceBudget(maxCalls: 1),
        ),
        throwsA(
          isA<WorkerError>().having(
            (error) => error.message,
            'message',
            contains('stopReason=output_limit'),
          ),
        ),
      );

      expect(
        logs.any(
          (line) =>
              line.contains('[EVIDENCE GENERATION TRUNCATED]') &&
              line.contains('source=initial_generation'),
        ),
        isTrue,
      );
      expect(
        logs.any((line) => line.contains('[JSON CORRECTIVE]')),
        isFalse,
      );
    });

    test('H non-truncated malformed evidence can use single repair', () async {
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
            return jsonEncode(task28f6542bMap1ValidStringsReconstructed);
          }
          return _brokenJson;
        },
      );

      final result = await processor.runJsonTask(
        prompt: PromptTemplates.summarizeMapChunk(
          chunkText: 'Order B410 and B426 issues.',
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
      expect(result['facts'], task28f6542bMap1ValidStringsReconstructed['facts']);
      expect(
        logs.any((line) => line.contains('[JSON CORRECTIVE] action=json_repair')),
        isTrue,
      );
    });

    test('I rejects wrong-schema repair output', () async {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      final logs = <String>[];
      final processor = QwenTaskProcessor(
        log: logs.add,
        runner: (prompt) async {
          if (prompt.contains('Fix the following broken JSON')) {
            return jsonEncode({
              'summary': 'public shape',
              'keyPoints': ['a'],
              'mainComplaint': '',
              'suggestedImprovement': '',
              'missingOrUnclear': [],
            });
          }
          return _brokenJson;
        },
      );

      await expectLater(
        processor.runJsonTask(
          prompt: PromptTemplates.summarizeMapChunk(
            chunkText: 'Chunk.',
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

      expect(
        logs.any((line) => line.contains('[JSON REPAIR FAILED]')),
        isTrue,
      );
    });

    test('J shares one corrective budget across stages', () async {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      final budget = CorrectiveInferenceBudget(maxCalls: 1);
      var calls = 0;
      final processor = QwenTaskProcessor(
        runner: (prompt) async {
          calls += 1;
          if (prompt.contains('Fix the following broken JSON')) {
            return jsonEncode(phase2EvidenceChunk2);
          }
          return _brokenJson;
        },
      );

      await processor.runJsonTask(
        prompt: PromptTemplates.summarizeMapChunk(
          chunkText: 'first',
          chunkIndex: 0,
          totalChunks: 2,
          chunkId: 'c' * 64,
        ),
        inferenceStage: SummarizeInferenceStage.mapEvidence,
        signingKey: 'sign',
        labeledFallback: false,
        correctiveBudget: budget,
      );

      await expectLater(
        processor.runJsonTask(
          prompt: PromptTemplates.summarizeMapChunk(
            chunkText: 'second',
            chunkIndex: 1,
            totalChunks: 2,
            chunkId: 'd' * 64,
          ),
          inferenceStage: SummarizeInferenceStage.mapEvidence,
          signingKey: 'sign',
          labeledFallback: false,
          correctiveBudget: budget,
        ),
        throwsA(
          isA<WorkerError>().having(
            (error) => error.message,
            'message',
            contains('corrective_budget_exhausted'),
          ),
        ),
      );

      expect(calls, 3);
    });

    test('K evidence guidance uses facts; final guidance uses keyPoints', () {
      final constraints = SummarizeTaskConstraintsV1(
        coverageAxes: const ['delivery timing', 'billing accuracy'],
      );
      final evidencePrompt = PromptTemplates.summarizeMapChunk(
        chunkText: 'body',
        chunkIndex: 0,
        totalChunks: 2,
        chunkId: 'c' * 64,
        constraints: constraints,
      );
      if (SummarizeEvidencePipeline.enabled) {
        expect(evidencePrompt, contains('facts should cover these topics'));
        expect(evidencePrompt, isNot(contains('keyPoints should cover')));
        expect(evidencePrompt, contains('arrays of strings only'));
        expect(evidencePrompt, contains(evidenceMapFactLengthGuidance));
        expect(evidencePrompt, contains('words when practical'));
        expect(evidencePrompt, contains('Format example only'));
      } else {
        expect(
          SummarizeConstraintRenderer.evidenceMapGuidanceBlock(constraints),
          contains('facts should cover'),
        );
      }
      final finalPrompt = PromptTemplates.summarizeReduceFinal(
        partialSummariesJson: '[]',
        chunkCount: 1,
        constraints: constraints,
      );
      expect(finalPrompt, contains('keyPoints'));
    });

    test('L valid evidence strings survive parsing unchanged', () async {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      final processor = QwenTaskProcessor(
        runner: (prompt) async =>
            jsonEncode(task28f6542bMap1ValidStringsReconstructed),
      );

      final result = await processor.runJsonTask(
        prompt: PromptTemplates.summarizeMapChunk(
          chunkText: 'body',
          chunkIndex: 0,
          totalChunks: 2,
          chunkId: 'c' * 64,
        ),
        inferenceStage: SummarizeInferenceStage.mapEvidence,
        signingKey: 'sign',
        labeledFallback: false,
        correctiveBudget: CorrectiveInferenceBudget(maxCalls: 1),
      );

      expect(result['facts'], task28f6542bMap1ValidStringsReconstructed['facts']);
      expect(
        result['openItems'],
        task28f6542bMap1ValidStringsReconstructed['openItems'],
      );
      expect(
        result['priority'],
        task28f6542bMap1ValidStringsReconstructed['priority'],
      );
    });
  });
}
