// NOT RUN — requires Phase 2 compile flag for evidence-v2 Map assertions:
// flutter test test/inference/llm/phase2_map_prompt_contract_test.dart
//   --dart-define=SUMMARIZE_EVIDENCE_V2=true

import 'package:edgemint_worker/inference/llm/hierarchical_reduce_bounds.dart';
import 'package:edgemint_worker/inference/llm/prompt_templates.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/llm/summarize_evidence_pipeline.dart';
import 'package:edgemint_worker/inference/llm/summarize_evidence_schema.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/customer_feedback_regression.dart';

void main() {
  group('Phase 2 evidence-v2 Map prompt contract (NOT RUN by default)', () {
    test('includes strings-only and short atomic-fact guidance', () {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      final prompt = PromptTemplates.summarizeMapChunk(
        chunkText: 'Sample chunk body.',
        chunkIndex: 0,
        totalChunks: 2,
        chunkId: 'a' * 64,
        userInstructions: customerFeedbackInstructions,
        constraints: customerFeedbackConstraints(),
      );

      expect(prompt, contains('arrays of strings only'));
      expect(prompt, contains('one distinct fact in one short sentence'));
      expect(prompt, contains('15–25 words'));
      expect(prompt, contains('Do not put a paragraph'));
      expect(prompt, contains('Split unrelated events'));
      expect(prompt, contains('Do not repeat the same fact'));
      expect(prompt, contains('close the arrays and object'));
      expect(prompt, isNot(contains('exactly 5 distinct facts (enforced)')));
    });

    test('format example is explicitly non-source material', () {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      final prompt = PromptTemplates.summarizeMapChunk(
        chunkText: 'Order B426 substitution issue.',
        chunkIndex: 0,
        totalChunks: 2,
        chunkId: 'a' * 64,
      );

      expect(prompt, contains('Format example only'));
      expect(prompt, contains('do not copy these facts'));
      expect(prompt, contains('Ticket R17 was closed on June 4.'));
      expect(prompt, isNot(contains('Order B426')));
      expect(prompt, isNot(contains('B443')));
    });

    test('customer instructions remain verbatim in evidence Map', () {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      final prompt = PromptTemplates.summarizeMapChunk(
        chunkText: 'body',
        chunkIndex: 0,
        totalChunks: 2,
        chunkId: 'a' * 64,
        userInstructions: customerFeedbackInstructions,
      );

      expect(
        prompt,
        contains('Customer instructions (apply when reading this chunk; verbatim):'),
      );
      expect(prompt, contains(customerFeedbackInstructionTailMarker));
    });

    test('no hard per-fact length validation or evidence-array cap in schema', () {
      // Wiring contract: schema validates types, not word counts or array caps.
      expect(
        SummarizeEvidenceSchema.validateStructure({
          'schemaVersion': '2',
          'facts': [List.filled(40, 'word').join(' ')],
          'openItems': [],
          'priority': '',
        }),
        isNull,
      );
      expect(
        SummarizeEvidenceSchema.validateStructure({
          'schemaVersion': '2',
          'facts': List.generate(20, (index) => 'fact $index'),
          'openItems': [],
          'priority': '',
        }),
        isNull,
      );
    });

    test('intermediate and final prompts unchanged by Map experiment', () {
      final intermediate = PromptTemplates.summarizeReduceIntermediate(
        partialSummariesJson: '[]',
        chunkCount: 2,
        userInstructions: customerFeedbackInstructions,
        constraints: customerFeedbackConstraints(),
      );
      final finalPrompt = PromptTemplates.summarizeReduceFinal(
        partialSummariesJson: '[]',
        chunkCount: 2,
        userInstructions: customerFeedbackInstructions,
        constraints: customerFeedbackConstraints(),
      );

      expect(intermediate, isNot(contains('Ticket R17')));
      expect(intermediate, isNot(contains('15–25 words')));
      expect(finalPrompt, isNot(contains('Ticket R17')));
      expect(finalPrompt, contains('keyPoints'));
    });

    test('legacy Map prompt unchanged when Phase 2 gate is off', () {
      if (SummarizeEvidencePipeline.enabled) {
        return;
      }
      final prompt = PromptTemplates.summarizeMapChunk(
        chunkText: 'body',
        chunkIndex: 0,
        totalChunks: 2,
        chunkId: 'a' * 64,
        constraints: customerFeedbackConstraints(),
      );

      expect(prompt, contains('keyPoints:'));
      expect(prompt, isNot(contains('Ticket R17')));
      expect(prompt, isNot(contains('schemaVersion'));
    });

    test('prompt reservation uses formatted Map wrapper through existing path', () {
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
      if (SummarizeEvidencePipeline.enabled) {
        expect(mapPrompt, contains('Format example only'));
      }
      expect(mapPrompt, contains(customerFeedbackInstructionTailMarker));
    });
  });
}
