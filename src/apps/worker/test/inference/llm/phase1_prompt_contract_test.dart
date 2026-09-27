import 'package:edgemint_worker/inference/llm/map_partial_validator.dart';
import 'package:edgemint_worker/inference/llm/prompt_templates.dart';
import 'package:edgemint_worker/inference/llm/summarize_evidence_pipeline.dart';
import 'package:edgemint_worker/inference/llm/summarize_output_validator.dart';
import 'package:edgemint_worker/inference/llm/summarize_task_constraints.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/customer_feedback_regression.dart';

void main() {
  group('Phase 1 prompt contract — intermediate vs final field rules', () {
    test('map template allows empty mainComplaint and suggestedImprovement', () {
      final prompt = PromptTemplates.summarizeMapChunk(
        chunkText: 'Sample chunk body.',
        chunkIndex: 0,
        totalChunks: 2,
        chunkId: 'a' * 64,
        userInstructions: customerFeedbackInstructions,
        constraints: customerFeedbackConstraints(),
      );

      if (SummarizeEvidencePipeline.enabled) {
        expect(prompt, contains('openItems: one concise string per unresolved question'));
        expect(prompt, contains('priority: concise paraphrase'));
        expect(prompt, isNot(contains('Identify the main complaint and one practical')));
      } else {
        expect(prompt, contains('Otherwise "".'));
        expect(prompt, contains('populate ONLY if this chunk explicitly states'));
        expect(prompt, isNot(contains('Identify the main complaint and one practical')));
      }
    });

    test('intermediate reduce allows empty complaint and improvement', () {
      final prompt = PromptTemplates.summarizeReduceIntermediate(
        partialSummariesJson: '[]',
        chunkCount: 2,
        userInstructions: customerFeedbackInstructions,
        constraints: customerFeedbackConstraints(),
      );

      if (SummarizeEvidencePipeline.enabled) {
        expect(prompt, contains('Do not create summary, keyPoints, mainComplaint'));
        expect(prompt, contains('facts and openItems are JSON arrays of strings only'));
        expect(prompt, isNot(contains('exactly 5 distinct facts (enforced)')));
      } else {
        expect(prompt, contains('mainComplaint: use explicit customer priority text'));
        expect(prompt, contains('if none,\n"".'));
        expect(prompt, contains('suggestedImprovement: one practical action if clearly supported; otherwise "".'));
        expect(prompt, isNot(contains('exactly 5 distinct facts (enforced)')));
        expect(prompt, isNot(contains('Merge missingOrUnclear entries from partials')));
      }
    });

    test('final reduce derives complaint and improvement from merged facts', () {
      final prompt = PromptTemplates.summarizeReduceFinal(
        partialSummariesJson: '[]',
        chunkCount: 2,
        userInstructions: customerFeedbackInstructions,
        constraints: customerFeedbackConstraints(),
      );

      if (SummarizeEvidencePipeline.enabled) {
        expect(prompt, contains('Produce the final customer-facing summary from merged evidence'));
        expect(prompt, contains('keyPoints:'));
        expect(prompt, contains('mainComplaint: reflect explicit customer priority'));
      } else {
        expect(prompt, contains('derive from the merged facts'));
        expect(prompt, contains('derive one from the merged facts'));
        expect(prompt, contains('exactly 5 distinct facts (enforced)'));
        expect(prompt, contains('One practical action addressing the main complaint'));
        expect(prompt, isNot(contains('otherwise "".')));
      }
    });

    test('MapPartialValidator accepts empty intermediate strings with keyPoints', () {
      final issues = MapPartialValidator.validate(
        partial: {
          'summary': '',
          'keyPoints': ['Order B410 arrived 40 minutes late.'],
          'mainComplaint': '',
          'suggestedImprovement': '',
          'missingOrUnclear': [],
        },
        generationTruncated: false,
      );
      expect(issues, isEmpty);
    });

    test('MapPartialValidator accepts five key points at map stage', () {
      final issues = MapPartialValidator.validate(
        partial: const {
          'summary': 'Chunk facts.',
          'keyPoints': ['a', 'b', 'c', 'd', 'e'],
          'mainComplaint': '',
          'suggestedImprovement': '',
          'missingOrUnclear': [],
        },
        generationTruncated: false,
        stopReason: 'model_eos',
      );
      expect(issues, isEmpty);
    });

    test('SummarizeOutputValidator rejects empty final mainComplaint and improvement', () {
      final result = SummarizeOutputValidator.validate(
        summary: {
          'summary': 'Final summary with enough words to pass structural checks easily.',
          'keyPoints': ['a', 'b', 'c', 'd', 'e'],
          'mainComplaint': '',
          'suggestedImprovement': '',
          'missingOrUnclear': [],
        },
        constraints: SummarizeTaskConstraintsV1.fromJson(const {
          'schemaVersion': '1',
          'keyPointCount': 5,
        }),
      );
      expect(result.passed, isFalse);
      expect(result.blockingViolations, contains('mainComplaint must be a non-empty string'));
      expect(result.blockingViolations, contains('suggestedImprovement must be a non-empty string'));
    });

    test('SummarizeOutputValidator accepts derived final strings', () {
      final result = SummarizeOutputValidator.validate(
        summary: {
          'summary': 'Customer reported substitution and billing issues across recent orders.',
          'keyPoints': ['a', 'b', 'c', 'd', 'e'],
          'mainComplaint': 'Unauthorized substitution despite disabled setting.',
          'suggestedImprovement': 'Audit substitution approval records.',
          'missingOrUnclear': ['Approval record not provided.'],
        },
        constraints: customerFeedbackConstraints(),
      );
      expect(result.passed, isTrue);
    });
  });
}
