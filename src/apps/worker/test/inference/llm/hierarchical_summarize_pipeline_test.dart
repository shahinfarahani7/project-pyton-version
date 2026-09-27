import 'dart:convert';

import 'package:edgemint_worker/contracts/worker_error.dart';
import 'package:edgemint_worker/inference/llm/context_budget_manager.dart';
import 'package:edgemint_worker/inference/llm/hierarchical_reduce_bounds.dart';
import 'package:edgemint_worker/inference/llm/hierarchical_summarize_pipeline.dart';
import 'package:edgemint_worker/inference/llm/prompt_templates.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/llm/summarize_evidence_pipeline.dart';
import 'package:edgemint_worker/inference/llm/summarize_task_constraints.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/customer_feedback_regression.dart';
import 'fixtures/semantic_chunk_golden.dart';
import 'fixtures/summarize_v2_prompt_matchers.dart';

Future<String> _summarizeMockRunner(String prompt) async {
  if (isEvidenceV2IntermediateReducePrompt(prompt)) {
    return jsonEncode({
      'schemaVersion': '2',
      'facts': ['alpha', 'beta'],
      'openItems': <String>[],
      'priority': '',
    });
  }
  if (prompt.contains('merged intermediate summary')) {
    return jsonEncode({
      'summary': 'Intermediate merged summary',
      'keyPoints': ['alpha', 'beta'],
      'mainComplaint': '',
      'suggestedImprovement': '',
      'missingOrUnclear': <String>[],
    });
  }
  if (isFinalReducePrompt(prompt)) {
    return jsonEncode({
      'summary': 'Final merged summary',
      'keyPoints': ['alpha', 'beta', 'gamma'],
      'mainComplaint': 'late delivery',
      'suggestedImprovement': 'improve live estimates',
      'missingOrUnclear': <String>[],
    });
  }
  if (prompt.contains('Extract evidence from this chunk')) {
    final indexMatch = RegExp(r'chunkIndex=(\d+)').firstMatch(prompt);
    final index = indexMatch?.group(1) ?? '0';
    if (isEvidenceV2MapChunkPrompt(prompt)) {
      return jsonEncode({
        'schemaVersion': '2',
        'facts': [
          'point-$index-a',
          'point-$index-b',
          'point-$index-c',
        ],
        'openItems': ['pending authorization unresolved'],
        'priority': '',
      });
    }
    return jsonEncode({
      'summary': 'Partial summary $index',
      'keyPoints': ['point-$index-a', 'point-$index-b', 'point-$index-c'],
      'mainComplaint': '',
      'suggestedImprovement': '',
      'missingOrUnclear': ['pending authorization unresolved'],
    });
  }
  return jsonEncode({
    'summary': 'Direct summary',
    'keyPoints': ['easy app', 'late delivery', 'inaccurate tracking'],
    'mainComplaint': 'late deliveries',
    'suggestedImprovement': 'use live driver location',
    'missingOrUnclear': <String>[],
  });
}

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
        runPromptJson: (prompt, {required inferenceStage}) async {
          calls += 1;
          return jsonDecode(await _summarizeMockRunner(prompt))
              as Map<String, dynamic>;
        },
      );

      final result = await pipeline.reduceLegacyPartials([
        {
          'summary': 'A',
          'keyPoints': ['one'],
          'missingOrUnclear': <String>[],
        },
        {
          'summary': 'B',
          'keyPoints': ['two'],
          'missingOrUnclear': <String>[],
        },
      ]);

      expect(calls, 1);
      expect(result['summary'], 'Final merged summary');
      expect(result['keyPoints'], contains('alpha'));
    });

    test('depth and inference bounds terminate fan-in recursion', () async {
      final pipeline = HierarchicalSummarizePipeline(
        contextBudget: ContextBudgetManager(),
        bounds: const HierarchicalReduceBounds(maxReduceDepth: 2),
        runPromptJson: (prompt, {required inferenceStage}) async => {
          'summary': 'Partial summary ${'x' * 5000}',
          'keyPoints': List.generate(20, (point) => 'point-$point ${'y' * 400}'),
          'mainComplaint': 'complaint',
          'suggestedImprovement': 'improvement',
          'missingOrUnclear': ['pending authorization unresolved'],
        },
      );

      await expectLater(
        pipeline.reduceLegacyPartials([
          {
            'summary': 'A ${'x' * 5000}',
            'keyPoints': List.generate(20, (point) => 'point-a-$point ${'y' * 400}'),
            'missingOrUnclear': <String>[],
          },
          {
            'summary': 'B ${'x' * 5000}',
            'keyPoints': List.generate(20, (point) => 'point-b-$point ${'y' * 400}'),
            'missingOrUnclear': <String>[],
          },
        ]),
        throwsA(isA<HierarchicalReduceExhaustedException>()),
      );
    });
  });

  group('QwenTaskProcessor summarize', () {
    test('short input uses direct textSummarize path', () async {
      var calls = 0;
      final prompts = <String>[];
      final processor = QwenTaskProcessor(
        runner: (prompt) async {
          calls += 1;
          prompts.add(prompt);
          return _summarizeMockRunner(prompt);
        },
      );

      final result = await processor.runSummarizeJsonTask(
        inputText: 'Short text for direct summarize.',
        signingKey: 'sign',
      );

      expect(calls, 1);
      expect(result['summary'], 'Direct summary');
      expect(prompts.single, contains('Source text:'));
      expect(prompts.single, isNot(contains('OCR text:')));
    });

    test('preserves full customer instructions in prompts', () async {
      final prompts = <String>[];
      final processor = QwenTaskProcessor(
        runner: (prompt) async {
          prompts.add(prompt);
          return jsonEncode({
            'summary': 'Customer reported multiple grocery delivery issues.',
            'keyPoints': [
              'Order A184 arrived late.',
              'Tracking showed five minutes away for an hour.',
              'Order A219 had an unauthorized substitution.',
              'Order A237 has a pending authorization for \$64.80.',
              'Support promised a \$12 refund within five business days.',
            ],
            'mainComplaint': 'Unauthorized dietary substitution.',
            'suggestedImprovement': 'Audit substitution approvals.',
            'missingOrUnclear': ['Whether pending authorization becomes a charge.'],
          });
        },
      );

      await processor.runSummarizeJsonTask(
        inputText: customerFeedbackSource,
        userInstructions: customerFeedbackInstructions,
        constraints: customerFeedbackConstraints(),
        signingKey: 'sign',
      );

      expect(
        customerFeedbackInstructions,
        customerFeedbackInstructions.trim(),
      );
      expect(
        customerFeedbackInstructions,
        contains(customerFeedbackInstructionTailMarker),
      );
      expect(
        prompts.any(
          (prompt) => prompt.contains(customerFeedbackInstructionTailMarker),
        ),
        isTrue,
      );
      expect(
        prompts.any((prompt) => prompt.contains('[INSTRUCTIONS TRIMMED]')),
        isFalse,
      );
    });

    test('constraint repair runs once then fails without retry loop', () async {
      var calls = 0;
      final processor = QwenTaskProcessor(
        runner: (prompt) async {
          calls += 1;
          return jsonEncode({
            'summary': 'Deliveries were late.',
            'keyPoints': ['one', 'two'],
            'mainComplaint': '',
            'suggestedImprovement': '',
            'missingOrUnclear': <String>[],
          });
        },
      );

      await expectLater(
        processor.runSummarizeJsonTask(
          inputText: _feedbackSource,
          constraints: SummarizeTaskConstraintsV1.fromJson(const {
            'schemaVersion': '1',
            'keyPointCount': 5,
          }),
          signingKey: 'sign',
        ),
        throwsA(
          isA<WorkerError>().having(
            (error) => error.retryable,
            'retryable',
            isFalse,
          ),
        ),
      );
      expect(calls, lessThanOrEqualTo(3));
    });

    test('keeps uncertainty items during normalization', () async {
      var calls = 0;
      final processor = QwenTaskProcessor(
        runner: (prompt) async {
          calls += 1;
          return jsonEncode({
            'summary': 'Billing and delivery issues were reported.',
            'keyPoints': [
              'One completed payment plus another pending authorization.',
              'Tracking estimates were unreliable.',
              'Substitution settings were disabled.',
            ],
            'mainComplaint': 'Unauthorized substitution.',
            'suggestedImprovement': 'Audit approvals.',
            'missingOrUnclear': [
              'Whether the pending authorization becomes another charge.',
            ],
          });
        },
      );

      final result = await processor.runSummarizeJsonTask(
        inputText:
            'One completed payment of \$64.80 and a pending authorization for \$64.80.',
        signingKey: 'sign',
      );

      expect(calls, 1);
      expect(result['missingOrUnclear'], isNotEmpty);
    });

    test(
      'long instructions keep every chunk prompt inside the budget',
      () async {
        final constraints = customerFeedbackConstraints();
        final processor = QwenTaskProcessor(
          runner: (prompt) async => _summarizeMockRunner(prompt),
        );
        final budget = processor.contextBudget;
        final heavier = List<String>.filled(
          3,
          semanticChunkGoldenInput(),
        ).join('\n\n');

        final plan = processor.planInputChunks(
          heavier,
          reservedPromptTokens: processor.summarizePromptReserveTokens(
            userInstructions: customerFeedbackInstructions,
            constraints: constraints,
          ),
        );

        for (final chunk in plan.chunks) {
          budget.ensureDirectInferenceOrThrow(
            prompt: PromptTemplates.summarizeMapChunk(
              chunkText: chunk.text,
              chunkIndex: chunk.chunkIndex,
              totalChunks: plan.totalChunks,
              chunkId: chunk.chunkId,
              userInstructions: customerFeedbackInstructions,
              constraints: constraints,
            ),
          );
        }

        budget.ensureDirectInferenceOrThrow(
          prompt: PromptTemplates.textSummarize(
            sourceText: heavier,
            userInstructions: customerFeedbackInstructions,
            constraints: constraints,
          ),
        );

        expect(plan.totalChunks, greaterThanOrEqualTo(1));
      },
    );

    test('map stage passes verbatim instructions and evidence guidance', () {
      final mapPrompt = PromptTemplates.summarizeMapChunk(
        chunkText: 'Order A184 arrived at 19:35.',
        chunkIndex: 0,
        totalChunks: 3,
        chunkId: 'a' * 64,
        userInstructions: customerFeedbackInstructions,
        constraints: customerFeedbackConstraints(),
      );

      expect(mapPrompt, contains(customerFeedbackInstructionTailMarker));
      expect(mapPrompt, contains('Customer instructions (apply when reading this chunk; verbatim)'));
      if (SummarizeEvidencePipeline.enabled) {
        expect(mapPrompt, contains('schemaVersion'));
        expect(mapPrompt, contains('facts and openItems are JSON arrays of strings only'));
        expect(mapPrompt, contains(evidenceMapFactLengthGuidance));
        expect(mapPrompt, isNot(contains('exactly 5 distinct facts (enforced)')));
        expect(mapPrompt, contains('informational; not automatically validated'));
      } else {
        expect(mapPrompt, contains('Prefer at most 6'));
        expect(mapPrompt, contains('distinct points, but include all critical'));
        expect(mapPrompt, contains('do not enforce final key-point count'));
        expect(mapPrompt, isNot(contains('exactly 5 distinct facts (enforced)')));
        expect(mapPrompt, contains('informational; not automatically validated'));
        expect(mapPrompt, contains('exactly these five keys and no others'));
      }

      final intermediateReduce = PromptTemplates.summarizeReduceIntermediate(
        partialSummariesJson: '[]',
        chunkCount: 2,
        userInstructions: customerFeedbackInstructions,
        constraints: customerFeedbackConstraints(),
      );
      expect(intermediateReduce, isNot(contains('exactly 5 distinct facts (enforced)')));
      expect(intermediateReduce, contains('sourceChunkIndexes'));
      expect(intermediateReduce, isNot(contains('Merge missingOrUnclear entries from partials')));

      final finalReduce = PromptTemplates.summarizeReduceFinal(
        partialSummariesJson: '[]',
        chunkCount: 2,
        userInstructions: customerFeedbackInstructions,
        constraints: customerFeedbackConstraints(),
      );
      expect(finalReduce, contains('exactly 5 distinct facts (enforced)'));
      expect(finalReduce, contains('Produce the final customer-facing summary'));
      expect(finalReduce, isNot(contains('Merge missingOrUnclear entries from partials')));
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
MISSING: none
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

      expect(prompts, hasLength(2));
      expect(prompts.last, contains('Answer in plain lines'));
      expect(result['summary'], contains('Deliveries slipped'));
      expect(result['keyPoints'], hasLength(3));
    });

    test('does not silently trim key points on summarize path', () async {
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

      expect(calls, 1);
      expect(result['keyPoints'], hasLength(4));
      expect(result['keyPoints'], contains('the milk arrived on time'));
    });

    test('honours structured keyPointCount constraints', () async {
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
        constraints: SummarizeTaskConstraintsV1.fromJson(const {
          'schemaVersion': '1',
          'keyPointCount': 5,
        }),
        signingKey: 'sign',
      );

      expect(result['keyPoints'], hasLength(5));
      expect(prompts.single, contains('exactly 5 distinct key points'));
    });

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
      expect(logs, contains(startsWith('[CHUNK FINAL RESPONSE]')));
    });
  });
}
