import 'dart:convert';

import 'package:edgemint_worker/inference/llm/hierarchical_reduce_bounds.dart';
import 'package:edgemint_worker/inference/llm/hierarchical_summarize_pipeline.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/llm/reduce_partial_envelope.dart';
import 'package:edgemint_worker/inference/llm/semantic_merge_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SemanticMergeValidator', () {
    test('treats group reduction as merge progress even when token mass grows', () {
      final partials = [
        {
          'summary': 'x' * 200,
          'keyPoints': ['a', 'b', 'c'],
          'missingOrUnclear': [],
        },
        {
          'summary': 'y' * 200,
          'keyPoints': ['d', 'e', 'f'],
          'missingOrUnclear': [],
        },
      ];
      final output = {
        'summary': 'z' * 800,
        'keyPoints': List.generate(12, (index) => 'expanded-point-$index ${'w' * 80}'),
        'mainComplaint': 'complaint text ${'q' * 120}',
        'suggestedImprovement': 'improvement text ${'r' * 120}',
        'missingOrUnclear': List.generate(4, (index) => 'open-item-$index ${'s' * 80}'),
      };
      expect(
        () => SemanticMergeValidator.assertDirectReduceProgress(
          inputPartials: partials,
          output: output,
          minTokenMassReductionRatioMilli: 50,
        ),
        returnsNormally,
        reason: '2 groups -> 1 group counts as progress before token mass is checked',
      );
    });

    test('detects non-shrinking merge when group count stays the same', () {
      expect(
        SemanticMergeValidator.madeProgress(
          beforeGroups: 2,
          afterGroups: 2,
          beforeTokenMass: 200,
          afterTokenMass: 250,
          minTokenMassReductionRatioMilli: 50,
        ),
        isFalse,
      );
    });

    test('accepts shrinking merge output', () {
      final partials = [
        {
          'summary': 'x' * 200,
          'keyPoints': ['a'],
          'missingOrUnclear': [],
        },
        {
          'summary': 'y' * 200,
          'keyPoints': ['b'],
          'missingOrUnclear': [],
        },
      ];
      expect(
        () => SemanticMergeValidator.assertDirectReduceProgress(
          inputPartials: partials,
          output: {
            'summary': 'merged',
            'keyPoints': ['a', 'b'],
            'missingOrUnclear': [],
          },
          minTokenMassReductionRatioMilli: 50,
        ),
        returnsNormally,
      );
    });
  });

  group('HierarchicalSummarizePipeline bounds', () {
    test('very long document exceeding chunk cap fails closed', () async {
      final pipeline = HierarchicalSummarizePipeline(
        contextBudget: QwenTaskProcessor().contextBudget,
        bounds: const HierarchicalReduceBounds(maxChunks: 2),
        runPromptJson: (prompt, {required inferenceStage}) async => {
          'summary': 'partial',
          'keyPoints': ['p'],
          'missingOrUnclear': [],
        },
      );
      await expectLater(
        pipeline.summarize(
          inputText: 'word ' * 5000,
          plan: QwenTaskProcessor().planInputChunks('word ' * 5000),
        ),
        throwsA(isA<HierarchicalReduceExhaustedException>()),
      );
    });

    test('reduce depth exhaustion stops recursive merge', () async {
      final pipeline = HierarchicalSummarizePipeline(
        contextBudget: QwenTaskProcessor().contextBudget,
        bounds: const HierarchicalReduceBounds(
          maxReduceDepth: 1,
          maxInferenceCalls: 64,
        ),
        runPromptJson: (prompt, {required inferenceStage}) async {
          if (prompt.contains('merged intermediate summary')) {
            return {
              'summary': 'merged',
              'keyPoints': ['m'],
              'missingOrUnclear': [],
            };
          }
          return {
            'summary': 'partial',
            'keyPoints': ['p'],
            'missingOrUnclear': [],
          };
        },
      );

      final oversizedPartials = List.generate(
        8,
        (index) => {
          'summary': 'chunk-$index ${'token ' * 500}',
          'keyPoints': List.generate(8, (point) => 'point-$index-$point ${'y' * 200}'),
          'missingOrUnclear': ['pending authorization unresolved'],
        },
      );

      await expectLater(
        pipeline.reduceLegacyPartials(oversizedPartials),
        throwsA(isA<HierarchicalReduceExhaustedException>()),
      );
    });

    test('reduce fan-in merges when output shrinks', () async {
      var calls = 0;
      final pipeline = HierarchicalSummarizePipeline(
        contextBudget: QwenTaskProcessor().contextBudget,
        runPromptJson: (prompt, {required inferenceStage}) async {
          calls += 1;
          if (prompt.contains('Combine the partial summaries into one final summary')) {
            return jsonDecode(
                  '{"summary":"Final merged summary","keyPoints":["alpha"],"missingOrUnclear":[]}',
                )
                as Map<String, dynamic>;
          }
          return {
            'summary': 'partial',
            'keyPoints': ['p'],
            'missingOrUnclear': [],
          };
        },
      );

      final result = await pipeline.reduceLegacyPartials([
        {
          'summary': 'A',
          'keyPoints': ['one'],
          'missingOrUnclear': [],
        },
        {
          'summary': 'B',
          'keyPoints': ['two'],
          'missingOrUnclear': [],
        },
      ]);

      expect(calls, 1);
      expect(result['summary'], 'Final merged summary');
    });
  });

  group('ReducePartialEnvelope', () {
    test('mergeGroup unions sourceChunkIndexes and processedCharRanges', () {
      final left = ReducePartialEnvelope.testSynthetic(
        chunkIndex: 0,
        partial: {'summary': 'A', 'keyPoints': ['one']},
      );
      final right = ReducePartialEnvelope.testSynthetic(
        chunkIndex: 1,
        partial: {'summary': 'B', 'keyPoints': ['two']},
      );
      final merged = ReducePartialEnvelope.mergeGroup(
        [left, right],
        {
          'summary': 'AB',
          'keyPoints': ['one', 'two'],
        },
      );

      expect(merged.sourceChunkIndexes, [0, 1]);
      expect(merged.processedCharRanges, hasLength(2));
      expect(merged.partial['summary'], 'AB');
    });

    test('encodeForPrompt wraps partials with provenance metadata', () {
      final encoded = ReducePartialEnvelope.encodeForPrompt([
        ReducePartialEnvelope.testSynthetic(
          chunkIndex: 2,
          partial: {
            'summary': 'chunk',
            'keyPoints': ['fact'],
            'missingOrUnclear': [],
          },
        ),
      ]);
      final decoded = jsonDecode(encoded) as List<dynamic>;
      expect(decoded.single['sourceChunkIndexes'], [2]);
      expect(decoded.single['partial']['summary'], 'chunk');
    });
  });
}
