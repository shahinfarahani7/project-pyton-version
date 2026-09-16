import 'dart:convert';

import 'package:edgemint_worker/inference/llm/hierarchical_reduce_bounds.dart';
import 'package:edgemint_worker/inference/llm/hierarchical_summarize_pipeline.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/llm/semantic_merge_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SemanticMergeValidator', () {
    test('detects non-shrinking direct reduce', () {
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
        'summary': 'z' * 400,
        'keyPoints': ['a', 'b', 'c', 'd', 'e', 'f'],
        'missingOrUnclear': [],
      };
      expect(
        () => SemanticMergeValidator.assertDirectReduceProgress(
          inputPartials: partials,
          output: output,
          minTokenMassReductionRatioMilli: 50,
        ),
        throwsA(isA<SemanticMergeNoProgressException>()),
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
        runPromptJson: (prompt) async => {
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
        runPromptJson: (prompt) async {
          if (prompt.contains('Combine the partial summaries')) {
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
          'summary': 'chunk-$index ${'token ' * 120}',
          'keyPoints': ['point-$index'],
          'missingOrUnclear': [],
        },
      );

      await expectLater(
        pipeline.reducePartials(oversizedPartials),
        throwsA(isA<HierarchicalReduceExhaustedException>()),
      );
    });

    test('reduce fan-in merges when output shrinks', () async {
      var calls = 0;
      final pipeline = HierarchicalSummarizePipeline(
        contextBudget: QwenTaskProcessor().contextBudget,
        runPromptJson: (prompt) async {
          calls += 1;
          if (prompt.contains('Combine the partial summaries')) {
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

      final result = await pipeline.reducePartials([
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
}
