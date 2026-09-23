import 'package:edgemint_worker/contracts/worker_error.dart';
import 'package:edgemint_worker/inference/llm/hierarchical_reduce_bounds.dart';
import 'package:edgemint_worker/inference/llm/prompt_templates.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/llm/reduce_partial_envelope.dart';
import 'package:edgemint_worker/inference/llm/summarize_constraint_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/customer_feedback_regression.dart';
import 'fixtures/semantic_chunk_golden.dart';

void main() {
  group('Phase 1 prompt wiring', () {
    test('mapGuidanceBlock emits coverage and billing only', () {
      final block = SummarizeConstraintRenderer.mapGuidanceBlock(
        customerFeedbackConstraints(),
      );
      expect(block, contains('delivery'));
      expect(block, contains('pending_not_confirmed_charge'));
      expect(block, isNot(contains('(enforced)')));
    });

    test('summarizePromptReserveTokens uses formatted map prompt with instructions', () {
      final processor = QwenTaskProcessor();
      final reserve = processor.summarizePromptReserveTokens(
        userInstructions: customerFeedbackInstructions,
        constraints: customerFeedbackConstraints(),
      );
      final mapPrompt = PromptTemplates.summarizeMapChunk(
        chunkText: '',
        chunkIndex: 0,
        totalChunks: 999,
        chunkId: '0' * 64,
        userInstructions: customerFeedbackInstructions,
        constraints: customerFeedbackConstraints(),
        evidenceTarget: HierarchicalReduceBounds.mapIntermediateEvidenceTarget,
      );
      expect(reserve, greaterThan(0));
      expect(mapPrompt, contains(customerFeedbackInstructionTailMarker));
    });

    test('_assertMapPromptFitsOrThrow rejects oversized instructions', () async {
      final oversized = List<String>.filled(400, 'instruction line ' * 20).join('\n');
      final processor = QwenTaskProcessor(
        runner: (prompt) async =>
            '{"summary":"x","keyPoints":["a"],"mainComplaint":"c","suggestedImprovement":"i","missingOrUnclear":[]}',
      );

      await expectLater(
        processor.runSummarizeJsonTask(
          inputText: semanticChunkGoldenInput(),
          userInstructions: oversized,
          signingKey: 'sign',
        ),
        throwsA(
          isA<WorkerError>().having(
            (error) => error.code,
            'code',
            WorkerErrorCode.invalidTask,
          ),
        ),
      );
    });
  });

  group('ReducePartialEnvelope recursive provenance', () {
    test('nested mergeGroup preserves all source indexes', () {
      final env0 = ReducePartialEnvelope.testSynthetic(
        chunkIndex: 0,
        partial: {'summary': '0', 'keyPoints': ['a']},
      );
      final env1 = ReducePartialEnvelope.testSynthetic(
        chunkIndex: 1,
        partial: {'summary': '1', 'keyPoints': ['b']},
      );
      final env2 = ReducePartialEnvelope.testSynthetic(
        chunkIndex: 2,
        partial: {'summary': '2', 'keyPoints': ['c']},
      );
      final env3 = ReducePartialEnvelope.testSynthetic(
        chunkIndex: 3,
        partial: {'summary': '3', 'keyPoints': ['d']},
      );

      final left = ReducePartialEnvelope.mergeGroup(
        [env0, env1],
        {'summary': '01', 'keyPoints': ['a', 'b']},
      );
      final right = ReducePartialEnvelope.mergeGroup(
        [env2, env3],
        {'summary': '23', 'keyPoints': ['c', 'd']},
      );
      final root = ReducePartialEnvelope.mergeGroup(
        [left, right],
        {'summary': 'final', 'keyPoints': ['a', 'b', 'c', 'd']},
      );

      expect(root.sourceChunkIndexes, [0, 1, 2, 3]);
      expect(root.processedCharRanges, hasLength(4));
    });
  });
}
