import 'dart:convert';

import '../inference/llm/fixtures/summarize_v2_prompt_matchers.dart';

/// Prompt-aware stub LLM runner that returns valid summarize JSON for map-reduce tests.
Future<String> summarizeContractMockRunner(String prompt) async {
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
