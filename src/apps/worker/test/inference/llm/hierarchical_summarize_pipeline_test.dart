import 'dart:convert';

import 'package:edgemint_worker/inference/llm/hierarchical_summarize_pipeline.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/semantic_chunk_golden.dart';

Future<String> _summarizeMockRunner(String prompt) async {
  if (prompt.contains('Combine the partial summaries')) {
    return jsonEncode({
      'summary': 'Final merged summary',
      'keyPoints': ['alpha', 'beta', 'gamma'],
      'missingOrUnclear': [],
    });
  }
  if (prompt.contains('Summarize only this chunk')) {
    final indexMatch = RegExp(r'chunkIndex=(\d+)').firstMatch(prompt);
    final index = indexMatch?.group(1) ?? '0';
    return jsonEncode({
      'summary': 'Partial summary $index',
      'keyPoints': ['point-$index'],
      'missingOrUnclear': [],
    });
  }
  return jsonEncode({
    'summary': 'Direct summary',
    'keyPoints': ['direct'],
    'missingOrUnclear': [],
  });
}

void main() {
  group('HierarchicalSummarizePipeline', () {
    test('reducePartials merges multiple map outputs', () async {
      var calls = 0;
      final pipeline = HierarchicalSummarizePipeline(
        contextBudget: QwenTaskProcessor().contextBudget,
        runPromptJson: (prompt) async {
          calls += 1;
          return jsonDecode(await _summarizeMockRunner(prompt)) as Map<String, dynamic>;
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

    test('long input uses map and reduce stages', () async {
      var calls = 0;
      final processor = QwenTaskProcessor(
        runner: (prompt) async {
          calls += 1;
          return _summarizeMockRunner(prompt);
        },
      );
      final input = semanticChunkGoldenInput();
      final plan = processor.planInputChunks(input);

      final result = await processor.runSummarizeJsonTask(
        inputText: input,
        signingKey: 'sign',
      );

      expect(plan.totalChunks, greaterThan(1));
      expect(calls, plan.totalChunks + 1);
      expect(result['summary'], 'Final merged summary');
      expect(result['keyPoints'], isNotEmpty);
    });
  });
}
