import 'dart:convert';

import 'package:edgemint_worker/inference/llm/context_budget_manager.dart';
import 'package:edgemint_worker/inference/llm/formatted_prompt_builder.dart';
import 'package:edgemint_worker/inference/llm/hierarchical_reduce_bounds.dart';
import 'package:edgemint_worker/inference/llm/hierarchical_summarize_pipeline.dart';
import 'package:edgemint_worker/inference/llm/prompt_templates.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/llm/summarize_reduce_budget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SummarizeReduceBudget', () {
    test('reduce budget uses actual encoded partials before inference', () async {    final logs = <String>[];
    var directReduceCalls = 0;
    final contextBudget = ContextBudgetManager();
    final pipeline = HierarchicalSummarizePipeline(
      contextBudget: contextBudget,
      log: logs.add,
      runPromptJson: (prompt) async {
        directReduceCalls += 1;
        return {
          'summary': 'merged',
          'keyPoints': ['a', 'b', 'c'],
          'mainComplaint': 'x',
          'suggestedImprovement': 'y',
          'missingOrUnclear': [],
        };
      },
    );

    final partials = List.generate(3, (index) {
      return {
        'summary': 'Partial summary ${'x' * 400}',
        'keyPoints': List.generate(6, (point) => 'fact-$index-$point ${'y' * 120}'),
        'mainComplaint': 'complaint-$index',
        'suggestedImprovement': 'improvement-$index',
        'missingOrUnclear': ['pending authorization unresolved'],
      };
    });

    final evaluation = SummarizeReduceBudget.evaluate(
      contextBudget: contextBudget,
      partials: partials,
      userInstructions: 'Analyze the customer feedback using only the provided content.',
      maxOutputTokens: 256,
    );

    await pipeline.reducePartials(partials);

    expect(
      logs.any((entry) => entry.startsWith('[CHUNK REDUCE BUDGET]')),
      isTrue,
    );
    expect(
      logs.any(
        (entry) =>
            entry.contains('partialsChars=${jsonEncode(partials).length}'),
      ),
      isTrue,
    );
    if (evaluation.requiresChunkPipeline) {
      expect(directReduceCalls, greaterThan(1));
    } else {
      expect(directReduceCalls, 1);
    }
    });

    test('oversized partials require bounded multi-level reduction', () async {
      final contextBudget = ContextBudgetManager();
      var reduceCalls = 0;
      final pipeline = HierarchicalSummarizePipeline(
        contextBudget: contextBudget,
        bounds: const HierarchicalReduceBounds(maxReduceDepth: 8),
        runPromptJson: (prompt) async {
          reduceCalls += 1;
          return {
            'summary': 'merged ${prompt.length}',
            'keyPoints': ['a'],
            'mainComplaint': 'x',
            'suggestedImprovement': 'y',
            'missingOrUnclear': [],
          };
        },
      );

      final partials = List.generate(8, (index) {
        return {
          'summary': 'Partial summary ${'x' * 500}',
          'keyPoints': List.generate(8, (point) => 'fact-$index-$point ${'y' * 160}'),
          'mainComplaint': 'complaint-$index',
          'suggestedImprovement': 'improvement-$index',
          'missingOrUnclear': ['pending authorization unresolved'],
        };
      });

      final evaluation = SummarizeReduceBudget.evaluate(
        contextBudget: contextBudget,
        partials: partials,
        userInstructions: null,
        maxOutputTokens: 300,
      );
      expect(evaluation.requiresChunkPipeline, isTrue);

      await pipeline.reducePartials(partials);
      expect(reduceCalls, greaterThan(1));
      expect(reduceCalls, lessThanOrEqualTo(128));
    });

    test('single oversized partial fails with reduce_fan_in_unresolved', () async {
      final contextBudget = ContextBudgetManager();
      final pipeline = HierarchicalSummarizePipeline(
        contextBudget: contextBudget,
        runPromptJson: (prompt) async => {
          'summary': 'merged',
          'keyPoints': ['a'],
          'mainComplaint': 'x',
          'suggestedImprovement': 'y',
          'missingOrUnclear': [],
        },
      );

      final oversizedPartial = {
        'summary': 'Partial summary ${'x' * 5000}',
        'keyPoints': List.generate(20, (point) => 'fact-$point ${'y' * 400}'),
        'mainComplaint': 'complaint',
        'suggestedImprovement': 'improvement',
        'missingOrUnclear': ['pending authorization unresolved'],
      };

      await expectLater(
        pipeline.reducePartials([oversizedPartial, oversizedPartial]),
        throwsA(isA<HierarchicalReduceExhaustedException>()),
      );
    });

    test('no known oversized prompt reaches mocked model', () async {
      final contextBudget = QwenTaskProcessor().contextBudget;
      final prompts = <String>[];
      final pipeline = HierarchicalSummarizePipeline(
        contextBudget: contextBudget,
        runPromptJson: (prompt) async {
          prompts.add(prompt);
          return {
            'summary': 'merged ${prompt.length}',
            'keyPoints': ['a', 'b', 'c'],
            'mainComplaint': 'x',
            'suggestedImprovement': 'y',
            'missingOrUnclear': [],
          };
        },
      );

      final partials = List.generate(6, (index) {
        return {
          'summary': 'Partial summary ${'x' * 450}',
          'keyPoints': List.generate(6, (point) => 'fact-$index-$point ${'y' * 120}'),
          'mainComplaint': 'complaint-$index',
          'suggestedImprovement': 'improvement-$index',
          'missingOrUnclear': ['pending authorization unresolved'],
        };
      });

      await pipeline.reducePartials(partials);

      for (final prompt in prompts) {
        final formatted = FormattedPromptBuilder.buildTaskPrompt(
          templateBody: prompt,
          systemInstruction: contextBudget.defaultSystemInstruction,
        );
        final evaluation = contextBudget.evaluateFormattedPrompt(
          formattedPrompt: formatted,
          maxOutputTokens: 300,
        );
        expect(
          evaluation.requiresChunkPipeline,
          isFalse,
          reason: 'mock received oversized prompt',
        );
      }
    });

    test('cancellation guard stops further reduce calls', () async {
      var calls = 0;
      final pipeline = HierarchicalSummarizePipeline(
        contextBudget: ContextBudgetManager(),
        runPromptJson: (prompt) async {
          calls += 1;
          return {
            'summary': 'merged',
            'keyPoints': ['a'],
            'mainComplaint': 'x',
            'suggestedImprovement': 'y',
            'missingOrUnclear': [],
          };
        },
      );

      final partials = [
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
      ];

      await expectLater(
        pipeline.reducePartials(
          partials,
          shouldContinue: () => false,
        ),
        throwsA(
          isA<HierarchicalReduceExhaustedException>().having(
            (error) => error.reason,
            'reason',
            'cancelled_or_deadline_exceeded',
          ),
        ),
      );
      expect(calls, 0);
    });
  });
}