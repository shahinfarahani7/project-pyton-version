import 'dart:convert';

import 'package:edgemint_worker/inference/llm/hierarchical_summarize_pipeline.dart';
import 'package:edgemint_worker/inference/llm/prompt_templates.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/semantic_chunk_golden.dart';

Future<String> _summarizeMockRunner(String prompt) async {
  if (prompt.contains('Combine the partial summaries')) {
    return jsonEncode({
      'summary': 'Final merged summary',
      'keyPoints': ['alpha', 'beta', 'gamma'],
      'mainComplaint': 'late delivery',
      'suggestedImprovement': 'improve live estimates',
      'missingOrUnclear': [],
    });
  }
  if (prompt.contains('Extract only what this chunk')) {
    final indexMatch = RegExp(r'chunkIndex=(\d+)').firstMatch(prompt);
    final index = indexMatch?.group(1) ?? '0';
    return jsonEncode({
      'summary': 'Partial summary $index',
      'keyPoints': ['point-$index-a', 'point-$index-b', 'point-$index-c'],
      'mainComplaint': 'complaint-$index',
      'suggestedImprovement': 'improvement-$index',
      'missingOrUnclear': [],
    });
  }
  return jsonEncode({
    'summary': 'Direct summary',
    'keyPoints': ['easy app', 'late delivery', 'inaccurate tracking'],
    'mainComplaint': 'late deliveries',
    'suggestedImprovement': 'use live driver location',
    'missingOrUnclear': [],
  });
}

/// Short customer feedback that stays on the direct summarize path whatever
/// the template overhead is, and still trips the delay/estimate checks.
const _feedbackSource =
    'The delivery app is easy to use. '
    'Three recent orders arrived more than 40 minutes late. '
    'Tracking kept showing five minutes away and support could not '
    'give an accurate arrival time.';

void main() {
  group('HierarchicalSummarizePipeline', () {
    test('reducePartials merges multiple map outputs', () async {
      var calls = 0;
      final pipeline = HierarchicalSummarizePipeline(
        contextBudget: QwenTaskProcessor().contextBudget,
        runPromptJson: (prompt) async {
          calls += 1;
          return jsonDecode(await _summarizeMockRunner(prompt))
              as Map<String, dynamic>;
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
      expect(result['keyPoints'], contains('alpha'));
    });
  });

  group('QwenTaskProcessor summarize', () {
    test('short input uses direct summarize path', () async {
      var calls = 0;
      final processor = QwenTaskProcessor(
        runner: (prompt) async {
          calls += 1;
          return _summarizeMockRunner(prompt);
        },
      );

      final result = await processor.runSummarizeJsonTask(
        inputText: 'Short text for direct summarize.',
        signingKey: 'sign',
      );

      expect(calls, 1);
      expect(result['summary'], 'Direct summary');
    });

    test('retries duplicate summary fields and removes extra keys', () async {
      var calls = 0;
      final prompts = <String>[];
      final processor = QwenTaskProcessor(
        runner: (prompt) async {
          calls += 1;
          prompts.add(prompt);
          if (calls == 1) {
            return jsonEncode({
              'summary': 'The app is easy to use.',
              'keyPoints': [
                'The app is easy to use.',
                'The app is easy to use.',
                'The app is easy to use.',
              ],
              'mainComplaint': 'The app is easy to use.',
              'suggestedImprovement': 'The app is easy to use.',
              'missingOrUnclear': ['The app is easy to use.'],
              'no_think': 'no_think',
            });
          }
          return jsonEncode({
            'summary':
                'The app is convenient, but recent deliveries were late.',
            'keyPoints': [
              'The app is easy to use.',
              'Three orders arrived over 40 minutes late.',
              'Tracking estimates and support timing were inaccurate.',
            ],
            'mainComplaint': 'Late deliveries and unreliable estimates.',
            'suggestedImprovement':
                'Use live driver location for delivery estimates.',
            'missingOrUnclear': <String>[],
          });
        },
      );

      final result = await processor.runSummarizeJsonTask(
        inputText: _feedbackSource,
        userInstructions:
            'Return three points, the main complaint, and one improvement.',
        signingKey: 'sign',
      );

      expect(calls, 2);
      expect(result['keyPoints'], hasLength(3));
      expect(result['mainComplaint'], contains('Late deliveries'));
      expect(result['suggestedImprovement'], contains('live driver'));
      expect(result, isNot(contains('no_think')));
      expect(prompts.last, contains('Customer instructions'));
      expect(prompts.last, contains('main complaint'));
    });

    test(
      'filters supported missing facts and repairs incomplete complaint',
      () async {
        const source =
            'The delivery app is easy to use and the product selection is good. '
            'The last three orders arrived at least 40 minutes late. '
            'Tracking kept showing arriving in 5 minutes even when the driver '
            'was far away, and support could not provide an accurate estimate.';
        var calls = 0;
        final prompts = <String>[];
        final processor = QwenTaskProcessor(
          runner: (prompt) async {
            calls += 1;
            prompts.add(prompt);
            if (calls == 1) {
              return jsonEncode({
                'summary':
                    'The app is useful, but recent deliveries were late.',
                'keyPoints': [
                  'The delivery app is easy to use.',
                  'The product selection is good.',
                  'Three orders arrived at least 40 minutes late.',
                ],
                'mainComplaint':
                    'The last three orders arrived at least 40 minutes late.',
                'suggestedImprovement': 'Provide accurate arrival times.',
                'missingOrUnclear': [
                  'The delivery app is easy to use.',
                  'The product selection is good.',
                ],
              });
            }
            return jsonEncode({
              'summary': 'The app is useful, but delivery reliability is poor.',
              'keyPoints': [
                'The delivery app is easy to use.',
                'Three recent orders arrived over 40 minutes late.',
                'Tracking and support provided inaccurate arrival estimates.',
              ],
              'mainComplaint':
                  'Repeated late deliveries and unreliable arrival estimates.',
              'suggestedImprovement':
                  'Use live driver location to update delivery estimates.',
              'missingOrUnclear': <String>[],
            });
          },
        );

        final result = await processor.runSummarizeJsonTask(
          inputText: source,
          signingKey: 'sign',
        );

        expect(calls, 1);
        expect(
          result['mainComplaint'],
          contains('arrival estimates were unreliable'),
        );
        expect(result['missingOrUnclear'], isEmpty);
        expect(prompts, hasLength(1));
      },
    );

    test(
      'long instructions keep every chunk prompt inside the budget',
      () async {
        const instructions =
            'Analyze the customer feedback using only the provided content.\n\n'
            'Return:\n'
            '- summary: A summary of no more than 80 words.\n'
            '- keyPoints: Exactly 5 distinct facts covering delivery, tracking, '
            'product issues, billing, and support.\n'
            '- mainComplaint: The customer main complaint, respecting their '
            'stated priority.\n'
            '- suggestedImprovement: One practical improvement based on the '
            'complaint.\n'
            '- missingOrUnclear: Only genuinely missing details.';
        final processor = QwenTaskProcessor(
          runner: (prompt) async => _summarizeMockRunner(prompt),
        );
        final budget = processor.contextBudget;
        // 1790 chars reproduces the feedback body that overflowed the budget
        // at 908 tokens once the customer instructions wrapped around it.
        final reported = ('${semanticChunkGoldenInput()} ' * 2).substring(
          0,
          1790,
        );

        final heavier = List<String>.filled(
          3,
          semanticChunkGoldenInput(),
        ).join('\n\n');

        for (final input in [reported, heavier]) {
          final plan = processor.planInputChunks(
            input,
            reservedPromptTokens: processor.summarizePromptReserveTokens(
              userInstructions: instructions,
              keyPointCount: 5,
            ),
          );

          if (plan.totalChunks == 1) {
            budget.ensureDirectInferenceOrThrow(
              prompt: PromptTemplates.documentSummarize(
                ocrText: input,
                userInstructions: instructions,
                keyPointCount: 5,
              ),
            );
            continue;
          }
          for (final chunk in plan.chunks) {
            budget.ensureDirectInferenceOrThrow(
              prompt: PromptTemplates.summarizeMapChunk(
                chunkText: chunk.text,
                chunkIndex: chunk.chunkIndex,
                totalChunks: plan.totalChunks,
                chunkId: chunk.chunkId,
              ),
            );
          }
        }

        expect(
          processor
              .planInputChunks(
                heavier,
                reservedPromptTokens: processor.summarizePromptReserveTokens(
                  userInstructions: instructions,
                  keyPointCount: 5,
                ),
              )
              .totalChunks,
          greaterThan(1),
        );
      },
    );

    test('map stage asks only for what its own chunk states', () {
      final mapPrompt = PromptTemplates.summarizeMapChunk(
        chunkText: 'Order A184 arrived at 19:35.',
        chunkIndex: 0,
        totalChunks: 3,
        chunkId: 'a' * 64,
      );

      // A chunk cannot cover topics it does not contain; forcing the customer's
      // count and topic list here is what made the model repeat itself.
      expect(mapPrompt, isNot(contains('Customer instructions')));
      expect(mapPrompt, isNot(contains('Exactly 5')));
      expect(mapPrompt, contains('at most 3 distinct facts'));
      expect(mapPrompt, contains('never the same fact twice'));
      expect(mapPrompt, contains('every array value must be an array'));
      // Rules shaped like `- name: value` get copied into the answer as
      // fields, which is how an unquoted DoNotInventFacts key appeared.
      expect(mapPrompt, isNot(contains('\n- ')));
      expect(
        mapPrompt,
        contains('exactly these five keys and no others'),
      );

      final reducePrompt = PromptTemplates.summarizeReduce(
        partialSummariesJson: '[]',
        chunkCount: 2,
        userInstructions: 'Exactly 5 distinct facts.',
        keyPointCount: 5,
      );
      expect(reducePrompt, contains('exactly 5 distinct short key points'));
      expect(reducePrompt, contains('Exactly 5 distinct facts.'));
    });

    test('rebuilds the summary from labelled lines when JSON is unusable', () async {
      final prompts = <String>[];
      final processor = QwenTaskProcessor(
        runner: (prompt) async {
          prompts.add(prompt);
          if (prompt.contains('Answer in plain lines')) {
            return '''
SUMMARY: Deliveries slipped on the last three orders.
POINT: Order A184 arrived at 19:35 instead of the promised window.
POINT: Tracking kept showing five minutes away.
POINT: Support could not give an accurate arrival time.
COMPLAINT: Late deliveries and unreliable arrival estimates.
IMPROVEMENT: Recalculate estimates from the driver location.
''';
          }
          return 'Sure! Here is the summary: the app is fine but deliveries '
              'are late.';
        },
      );

      final result = await processor.runSummarizeJsonTask(
        inputText: _feedbackSource,
        signingKey: 'sign',
      );

      // Two calls: the unusable JSON, then the labelled re-ask. The broken
      // reply is never sent back for the model to repair.
      expect(prompts, hasLength(2));
      expect(prompts.last, contains('Answer in plain lines'));
      expect(prompts.last, isNot(contains('Fix the following broken JSON')));
      expect(result['summary'], contains('Deliveries slipped'));
      expect(result['keyPoints'], hasLength(3));
      expect(result['mainComplaint'], contains('Late deliveries'));
      expect(result['missingOrUnclear'], isEmpty);
    });

    test('trims a looping oversized reply without a second call', () async {
      var calls = 0;
      final processor = QwenTaskProcessor(
        runner: (prompt) async {
          calls += 1;
          return jsonEncode({
            'summary': 'Deliveries slipped and the wrong milk arrived.',
            'keyPoints': [
              'Three recent orders arrived more than 40 minutes late',
              'Tracking estimates stayed inaccurate until delivery',
              'Support could not give an accurate arrival time',
              // The model then loops until the output budget is spent.
              ...List.filled(25, 'the milk arrived on time'),
            ],
            'mainComplaint': 'Late deliveries and unreliable estimates.',
            'suggestedImprovement': 'Recalculate estimates from driver GPS.',
            'missingOrUnclear': <String>[],
          });
        },
      );

      final result = await processor.runSummarizeJsonTask(
        inputText: _feedbackSource,
        signingKey: 'sign',
      );

      // The oversized reply is cut locally. Asking the model to compact it
      // returned the same loop and dropped mainComplaint with it.
      expect(calls, 1);
      expect(result['keyPoints'], hasLength(3));
      expect(result['keyPoints'], isNot(contains('the milk arrived on time')));
      expect(result['mainComplaint'], 'Late deliveries and unreliable estimates.');
      expect(
        result['suggestedImprovement'],
        'Recalculate estimates from driver GPS.',
      );
    });

    test('drops key points copied verbatim from the source', () async {
      var calls = 0;
      final processor = QwenTaskProcessor(
        runner: (prompt) async {
          calls += 1;
          return jsonEncode({
            'summary': 'Recent orders ran late and estimates were wrong.',
            'keyPoints': [
              'The delivery app is easy to use.',
              'Three orders were over 40 minutes late.',
              'Tracking estimates stayed inaccurate.',
              'Support gave no accurate arrival time.',
            ],
            'mainComplaint': 'Late deliveries and unreliable estimates.',
            'suggestedImprovement': 'Recalculate estimates from driver GPS.',
            'missingOrUnclear': <String>[],
          });
        },
      );

      final result = await processor.runSummarizeJsonTask(
        inputText: _feedbackSource,
        signingKey: 'sign',
      );

      expect(calls, 1);
      expect(result['keyPoints'], hasLength(3));
      expect(
        result['keyPoints'],
        isNot(contains('The delivery app is easy to use.')),
      );
    });

    test('honours a requested key point count above the default', () async {
      final prompts = <String>[];
      final processor = QwenTaskProcessor(
        runner: (prompt) async {
          prompts.add(prompt);
          return jsonEncode({
            'summary': 'Delivery reliability dropped across recent orders.',
            'keyPoints': [
              'Order A184 arrived 35 minutes late.',
              'Tracking estimates stayed inaccurate.',
              'One produce item was missing.',
              'A refund was charged twice.',
              'Support replied without a resolution.',
            ],
            'mainComplaint': 'Repeated late deliveries.',
            'suggestedImprovement': 'Recalculate estimates from driver GPS.',
            'missingOrUnclear': <String>[],
          });
        },
      );

      final result = await processor.runSummarizeJsonTask(
        inputText: 'Deliveries slipped and billing was wrong.',
        userInstructions:
            'Return keyPoints: Exactly 5 distinct facts covering delivery, '
            'tracking, product issues, billing, and support.',
        signingKey: 'sign',
      );

      expect(result['keyPoints'], hasLength(5));
      expect(prompts.single, contains('exactly 5 distinct key points'));
    });

    test(
      'accepts a repaired summary that is short of the requested count',
      () async {
        var calls = 0;
        final processor = QwenTaskProcessor(
          runner: (prompt) async {
            calls += 1;
            if (calls == 1) {
              return jsonEncode({
                'summary': 'Deliveries were late.',
                'keyPoints': ['Deliveries were late.'],
                'mainComplaint': '',
                'suggestedImprovement': '',
                'missingOrUnclear': <String>[],
              });
            }
            return jsonEncode({
              'summary': 'Deliveries slipped and billing was wrong.',
              'keyPoints': [
                'Order A184 arrived 35 minutes late.',
                'Tracking estimates stayed inaccurate.',
                'A refund was charged twice.',
              ],
              'mainComplaint': 'Repeated late deliveries.',
              'suggestedImprovement': 'Recalculate estimates from driver GPS.',
              'missingOrUnclear': <String>[],
            });
          },
        );

        final result = await processor.runSummarizeJsonTask(
          inputText: 'Deliveries slipped and billing was wrong.',
          userInstructions: 'Return exactly 5 key points.',
          signingKey: 'sign',
        );

        expect(calls, 2);
        expect(result['keyPoints'], hasLength(3));
      },
    );

    test('long input uses map and reduce stages', () async {
      var calls = 0;
      final logs = <String>[];
      final processor = QwenTaskProcessor(
        log: logs.add,
        runner: (prompt) async {
          calls += 1;
          return _summarizeMockRunner(prompt);
        },
      );
      final input = List<String>.filled(
        20,
        semanticChunkGoldenInput(),
      ).join('\n\n');
      final plan = processor.planInputChunks(
        input,
        reservedPromptTokens: processor.summarizePromptReserveTokens(),
      );

      final result = await processor.runSummarizeJsonTask(
        inputText: input,
        signingKey: 'sign',
      );

      expect(plan.totalChunks, greaterThan(1));
      expect(calls, greaterThanOrEqualTo(plan.totalChunks + 1));
      expect(result['summary'], 'Final merged summary');
      expect(result['keyPoints'], isNotEmpty);
      expect(logs, contains(startsWith('[CHUNK PLAN]')));
      expect(
        logs.where((entry) => entry.startsWith('[CHUNK REQUEST]')).length,
        plan.totalChunks,
      );
      expect(
        logs.where((entry) => entry.startsWith('[CHUNK RESPONSE]')).length,
        plan.totalChunks,
      );
      expect(logs, contains(startsWith('[CHUNK FINAL RESPONSE]')));
    });
  });
}
