import 'dart:convert';

import 'package:edgemint_worker/inference/llm/prompt_templates.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/llm/summarize_inference_stage.dart';
import 'package:edgemint_worker/inference/llm/reduce_partial_envelope.dart';
import 'package:edgemint_worker/inference/llm/semantic_chunk_engine.dart';
import 'package:edgemint_worker/validation/json_output_validator.dart';
import 'package:flutter_test/flutter_test.dart';

const _sevenDistinctFacts = [
  'Order B410 arrived 40 minutes late.',
  'Order B426 substituted regular milk.',
  'Substitution setting was disabled on B426.',
  'Order B443 had duplicate pending charges.',
  'Refund for incorrect milk is still pending.',
  'Customer declined a coupon offer.',
  'Support did not explain approval evidence.',
];

Map<String, dynamic> _mapPartialWithFacts(List<String> keyPoints) => {
  'summary': 'Seven distinct chunk facts for reduce merge.',
  'keyPoints': keyPoints,
  'mainComplaint': '',
  'suggestedImprovement': '',
  'missingOrUnclear': ['Pending refund timing unclear.'],
};

SemanticChunk _testChunk() => SemanticChunk(
  chunkId: 'c' * 64,
  chunkIndex: 0,
  inputHash: 'hash',
  text: 'Chunk body with multiple orders and payment issues.',
  processedRange: const ProcessedRange(startChar: 0, endChar: 120),
  estimatedTokens: 40,
  overlapChars: 0,
);

void main() {
  group('Map evidence preservation on summarize path', () {
    test('preserves seven distinct keyPoints through parse and reduce envelope',
        () async {
      final logs = <String>[];
      final processor = QwenTaskProcessor(
        log: logs.add,
        runner: (prompt) async {
          expect(prompt, contains('Chunk metadata:'));
          return jsonEncode(_mapPartialWithFacts(_sevenDistinctFacts));
        },
      );

      final parsed = await processor.runJsonTask(
        prompt: PromptTemplates.summarizeMapChunk(
          chunkText: _testChunk().text,
          chunkIndex: 0,
          totalChunks: 2,
          chunkId: _testChunk().chunkId,
        ),
        inferenceStage: SummarizeInferenceStage.mapEvidence,
        signingKey: 'sign',
        maxArrayItems: 4,
        correctiveBudget: CorrectiveInferenceBudget(),
      );

      expect(
        (parsed['keyPoints'] as List).map((item) => item.toString()).toList(),
        _sevenDistinctFacts,
      );

      final envelope = ReducePartialEnvelope.fromMapStage(
        chunk: _testChunk(),
        partial: parsed,
      );
      final encoded = ReducePartialEnvelope.encodeForPrompt([envelope]);
      final roundTrip =
          (jsonDecode(encoded) as List).single as Map<String, dynamic>;
      final roundTripPoints =
          (roundTrip['partial'] as Map<String, dynamic>)['keyPoints'] as List;

      expect(roundTripPoints.map((item) => item.toString()).toList(),
          _sevenDistinctFacts);
      expect(logs.any((line) => line.contains('[JSON TRIMMED]')), isFalse);
      expect(logs.any((line) => line.contains('[MODEL COMPACT RETRY]')), isFalse);
    });

    test('trimToLimits is bypassed on summarize Map even with maxArrayItems=4',
        () async {
      final oversized = _mapPartialWithFacts(_sevenDistinctFacts);
      final wouldTrimToFour = JsonOutputValidator.trimToLimits(
        oversized,
        maxArrayItems: 4,
      );
      expect((wouldTrimToFour['keyPoints'] as List).length, 4);

      final processor = QwenTaskProcessor(
        runner: (prompt) async => jsonEncode(oversized),
      );
      final parsed = await processor.runJsonTask(
        prompt: PromptTemplates.summarizeMapChunk(
          chunkText: _testChunk().text,
          chunkIndex: 0,
          totalChunks: 2,
          chunkId: _testChunk().chunkId,
        ),
        inferenceStage: SummarizeInferenceStage.mapEvidence,
        signingKey: 'sign',
        maxArrayItems: 4,
        correctiveBudget: CorrectiveInferenceBudget(),
      );

      expect((parsed['keyPoints'] as List).length, 7);
    });
  });
}
