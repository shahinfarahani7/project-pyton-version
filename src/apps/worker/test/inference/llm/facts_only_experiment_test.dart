// NOT RUN — evidence-v2 and armed-diagnostic cases require:
// flutter test test/inference/llm/facts_only_experiment_test.dart
//   --dart-define=SUMMARIZE_EVIDENCE_V2=true
//   --dart-define=SUMMARIZE_DIAGNOSTIC_MAP_EVIDENCE=true

import 'dart:convert';

import 'package:edgemint_worker/contracts/worker_error.dart';
import 'package:edgemint_worker/inference/llm/diagnostic/facts_only_experiment.dart';
import 'package:edgemint_worker/inference/llm/diagnostic/summarize_map_evidence_diagnostic_fixture.dart';
import 'package:edgemint_worker/inference/llm/diagnostic/summarize_map_prompt_variant.dart';
import 'package:edgemint_worker/inference/llm/prompt_templates.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/llm/summarize_diagnostic_map.dart';
import 'package:edgemint_worker/inference/llm/summarize_evidence_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

const _factsOnlyJson =
    '{"schemaVersion":"2","facts":["R201 arrived 20 minutes after its delivery window.",'
    '"The customer says their main concern is X."],"openItems":[],"priority":""}';

const _validClassification =
    '{"schemaVersion":"diag_classify_1","priority":{"text":"X","supportingFactIndexes":[1]},'
    '"openItems":[]}';

/// Classification-only field instructions that must not appear in facts-only.
const _conflictingFieldInstructions = [
  'Field assignment',
  'mainComplaint or missingOrUnclear apply',
  'put that concern here only',
  'Put the stated\n  main concern in priority',
  '- openItems: one concise string per unresolved question',
  '- priority: concise paraphrase',
];

String _render(
  SummarizeMapPromptVariant variant,
  SummarizeMapEvidenceDiagnosticFixtureId fixture,
) =>
    PromptTemplates.summarizeMapChunkEvidenceDiagnostic(
      chunkText: sourceForMapEvidenceDiagnosticFixture(fixture),
      chunkIndex: 0,
      totalChunks: 1,
      chunkId: 'a' * 64,
      userInstructions: summarizeMapEvidenceDiagnosticInstructions,
      constraints: summarizeMapEvidenceDiagnosticConstraints(),
      promptVariant: variant,
    );

QwenTaskProcessor _scripted(List<String> responses, List<String> prompts) {
  var call = 0;
  return QwenTaskProcessor(
    runner: (prompt) async {
      prompts.add(prompt);
      return responses[call++];
    },
  );
}

void main() {
  group('Facts-only rendering (NOT RUN by default)', () {
    test('facts_only parses and is not the default', () {
      expect(
        parseSummarizeMapPromptVariant('facts_only'),
        SummarizeMapPromptVariant.factsOnly,
      );
      const raw = String.fromEnvironment(
        summarizeMapPromptVariantConfigurationName,
      );
      if (raw.isEmpty) {
        expect(
          SummarizeDiagnosticMap.promptVariant,
          SummarizeMapPromptVariant.current,
        );
      }
    });

    test('production Map prompt unchanged and free of facts-only text', () {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      for (final fixture in SummarizeMapEvidenceDiagnosticFixtureId.values) {
        final production = PromptTemplates.summarizeMapChunk(
          chunkText: sourceForMapEvidenceDiagnosticFixture(fixture),
          chunkIndex: 0,
          totalChunks: 1,
          chunkId: 'a' * 64,
          userInstructions: summarizeMapEvidenceDiagnosticInstructions,
          constraints: summarizeMapEvidenceDiagnosticConstraints(),
        );
        expect(_render(SummarizeMapPromptVariant.current, fixture), production);
        expect(production, isNot(contains('Evidence recording')));
      }
    });

    for (final fixture in SummarizeMapEvidenceDiagnosticFixtureId.values) {
      test('facts_only has no conflicting field instructions (${fixture.logLabel})', () {
        if (!SummarizeEvidencePipeline.enabled) {
          return;
        }
        final prompt = _render(SummarizeMapPromptVariant.factsOnly, fixture);
        for (final conflicting in _conflictingFieldInstructions) {
          expect(prompt, isNot(contains(conflicting)), reason: conflicting);
        }
        expect(
          prompt,
          contains('{"schemaVersion":"2","facts":["..."],"openItems":[],"priority":""}'),
        );
        expect(prompt, contains('Evidence recording'));
        expect(prompt, contains('a later explicit update to the same'));
        expect(prompt, contains('who claimed, denied, or'));
      });

      test('facts_only keeps full fixture and verbatim instructions (${fixture.logLabel})', () {
        if (!SummarizeEvidencePipeline.enabled) {
          return;
        }
        final prompt = _render(SummarizeMapPromptVariant.factsOnly, fixture);
        final source = sourceForMapEvidenceDiagnosticFixture(fixture);
        expect(prompt, contains('Chunk text:\n---\n$source\n---'));
        expect(prompt, contains(summarizeMapEvidenceDiagnosticInstructions));
        expect(prompt, contains('Soft JSON size target: about'));
      });
    }
  });

  group('Classification prompt isolation', () {
    test('contains exactly the snapshot facts and no source or instructions', () {
      const facts = ['Fact zero.', 'Fact one with "quotes".'];
      final prompt = PromptTemplates.factsClassificationDiagnostic(facts: facts);
      expect(prompt, contains('[0] ${jsonEncode(facts[0])}'));
      expect(prompt, contains('[1] ${jsonEncode(facts[1])}'));
      expect(prompt, isNot(contains('[2]')));
      for (final fixture in SummarizeMapEvidenceDiagnosticFixtureId.values) {
        expect(
          prompt,
          isNot(contains(sourceForMapEvidenceDiagnosticFixture(fixture))),
        );
      }
      expect(prompt, isNot(contains(summarizeMapEvidenceDiagnosticInstructions)));
      for (final answer in ['R201', 'R202', 'R203', r'$72.40', 'lactose']) {
        expect(prompt, isNot(contains(answer)), reason: answer);
      }
    });
  });

  group('Classification schema', () {
    Map<String, dynamic> parse(String json) =>
        jsonDecode(json) as Map<String, dynamic>;

    test('accepts a valid classification', () {
      expect(
        FactsClassificationSchema.validate(parse(_validClassification), factCount: 2),
        isNull,
      );
    });

    test('rejects invalid support indexes', () {
      final cases = {
        'out_of_bounds': '{"schemaVersion":"diag_classify_1","priority":{"text":"X","supportingFactIndexes":[2]},"openItems":[]}',
        'negative': '{"schemaVersion":"diag_classify_1","priority":{"text":"X","supportingFactIndexes":[-1]},"openItems":[]}',
        'duplicated': '{"schemaVersion":"diag_classify_1","priority":{"text":"X","supportingFactIndexes":[0,0]},"openItems":[]}',
        'non_integer': '{"schemaVersion":"diag_classify_1","priority":{"text":"X","supportingFactIndexes":[0.5]},"openItems":[]}',
        'text_without_index': '{"schemaVersion":"diag_classify_1","priority":{"text":"X","supportingFactIndexes":[]},"openItems":[]}',
        'empty_with_index': '{"schemaVersion":"diag_classify_1","priority":{"text":"","supportingFactIndexes":[0]},"openItems":[]}',
        'open_item_no_index': '{"schemaVersion":"diag_classify_1","priority":{"text":"","supportingFactIndexes":[]},"openItems":[{"text":"Y","supportingFactIndexes":[]}]}',
        'open_item_out_of_bounds': '{"schemaVersion":"diag_classify_1","priority":{"text":"","supportingFactIndexes":[]},"openItems":[{"text":"Y","supportingFactIndexes":[5]}]}',
      };
      cases.forEach((label, json) {
        expect(
          FactsClassificationSchema.validate(parse(json), factCount: 2),
          isNotNull,
          reason: label,
        );
      });
    });

    test('rejects wrong keys and schema version', () {
      expect(
        FactsClassificationSchema.validate(
          parse('{"schemaVersion":"diag_classify_1","priority":{"text":"","supportingFactIndexes":[]},"openItems":[],"facts":[]}'),
          factCount: 2,
        ),
        isNotNull,
      );
      expect(
        FactsClassificationSchema.validate(
          parse('{"schemaVersion":"2","priority":{"text":"","supportingFactIndexes":[]},"openItems":[]}'),
          factCount: 2,
        ),
        isNotNull,
      );
    });
  });

  group('Facts-only experiment runs (NOT RUN by default)', () {
    test('extraction snapshot is immutable and hashed', () async {
      if (!SummarizeDiagnosticMap.armed) {
        return;
      }
      final prompts = <String>[];
      final processor = _scripted([_factsOnlyJson], prompts);
      final result = await processor.runIsolatedMapEvidenceDiagnostic(
        signingKey: 'test',
        promptVariant: SummarizeMapPromptVariant.factsOnly,
      );
      final snapshot = result.factsSnapshot!;
      expect(result.experimentId, snapshot.experimentId);
      expect(snapshot.extractionRunId, result.runId);
      expect(() => snapshot.facts.add('x'), throwsUnsupportedError);
      expect(snapshot.facts, hasLength(2));
      expect(prompts.single, contains('Evidence recording'));
    });

    test('extraction with populated priority is rejected without a snapshot', () async {
      if (!SummarizeDiagnosticMap.armed) {
        return;
      }
      final processor = _scripted([
        '{"schemaVersion":"2","facts":["A."],"openItems":[],"priority":"A"}',
      ], []);
      final result = await processor.runIsolatedMapEvidenceDiagnostic(
        signingKey: 'test',
        promptVariant: SummarizeMapPromptVariant.factsOnly,
      );
      expect(result.failure, isNotNull);
      expect(result.factsSnapshot, isNull);
    });

    test('truncated extraction produces no snapshot', () async {
      if (!SummarizeDiagnosticMap.armed) {
        return;
      }
      final processor = QwenTaskProcessor(
        runner: (_) async => '{"schemaVersion":"2","facts":["x"',
        testRunnerTruncated: true,
        testRunnerStopReason: 'output_limit',
      );
      final result = await processor.runIsolatedMapEvidenceDiagnostic(
        signingKey: 'test',
        promptVariant: SummarizeMapPromptVariant.factsOnly,
      );
      expect(result.truncated, isTrue);
      expect(result.factsSnapshot, isNull);
    });

    test('classification receives only the exact snapshot facts', () async {
      if (!SummarizeDiagnosticMap.armed) {
        return;
      }
      final prompts = <String>[];
      final processor = _scripted([_factsOnlyJson, _validClassification], prompts);
      final extraction = await processor.runIsolatedMapEvidenceDiagnostic(
        signingKey: 'test',
        fixtureId: SummarizeMapEvidenceDiagnosticFixtureId.narrative,
        promptVariant: SummarizeMapPromptVariant.factsOnly,
      );
      final snapshot = extraction.factsSnapshot!;
      final result = await processor.runFactsOnlyClassificationDiagnostic(
        signingKey: 'test',
        snapshot: snapshot,
      );
      final classificationPrompt = prompts[1];
      for (var index = 0; index < snapshot.facts.length; index++) {
        expect(
          classificationPrompt,
          contains('[$index] ${jsonEncode(snapshot.facts[index])}'),
        );
      }
      expect(
        classificationPrompt,
        isNot(contains(sourceForMapEvidenceDiagnosticFixture(
          SummarizeMapEvidenceDiagnosticFixtureId.narrative,
        ))),
      );
      expect(
        classificationPrompt,
        isNot(contains(summarizeMapEvidenceDiagnosticInstructions)),
      );
      expect(result.factsSha256, snapshot.factsSha256);
      expect(result.experimentId, snapshot.experimentId);
      expect(result.extractionRunId, extraction.runId);
      expect(result.validatedClassification, isNotNull);
      expect(result.validatedClassification!.containsKey('summary'), isFalse);
      expect(result.semanticSupportCheck, 'manual_required');
      expect(prompts, hasLength(2));
    });

    test('classification runs at most once per extraction', () async {
      if (!SummarizeDiagnosticMap.armed) {
        return;
      }
      final processor = _scripted([_factsOnlyJson, _validClassification], []);
      final snapshot = (await processor.runIsolatedMapEvidenceDiagnostic(
        signingKey: 'test',
        promptVariant: SummarizeMapPromptVariant.factsOnly,
      ))
          .factsSnapshot!;
      await processor.runFactsOnlyClassificationDiagnostic(
        signingKey: 'test',
        snapshot: snapshot,
      );
      expect(
        () => processor.runFactsOnlyClassificationDiagnostic(
          signingKey: 'test',
          snapshot: snapshot,
        ),
        throwsA(isA<WorkerError>()),
      );
    });

    test('one corrective allowance is shared across both steps', () async {
      if (!SummarizeDiagnosticMap.armed) {
        return;
      }
      final prompts = <String>[];
      final processor = _scripted([
        'not json',
        _factsOnlyJson,
        'still not json',
      ], prompts);
      final extraction = await processor.runIsolatedMapEvidenceDiagnostic(
        signingKey: 'test',
        promptVariant: SummarizeMapPromptVariant.factsOnly,
      );
      expect(extraction.correctiveInferenceCalls, 1);
      expect(extraction.firstPassSuccess, isFalse);
      expect(extraction.repairedSuccess, isTrue);
      final result = await processor.runFactsOnlyClassificationDiagnostic(
        signingKey: 'test',
        snapshot: extraction.factsSnapshot!,
      );
      expect(result.failure, isNotNull);
      expect(result.correctiveCallsThisStep, 0);
      expect(result.correctiveCallsExperimentTotal, 1);
      expect(prompts, hasLength(3));
    });

    test('invalid support index fails classification without repair', () async {
      if (!SummarizeDiagnosticMap.armed) {
        return;
      }
      final prompts = <String>[];
      final processor = _scripted([
        _factsOnlyJson,
        '{"schemaVersion":"diag_classify_1","priority":{"text":"X","supportingFactIndexes":[9]},"openItems":[]}',
      ], prompts);
      final snapshot = (await processor.runIsolatedMapEvidenceDiagnostic(
        signingKey: 'test',
        promptVariant: SummarizeMapPromptVariant.factsOnly,
      ))
          .factsSnapshot!;
      final result = await processor.runFactsOnlyClassificationDiagnostic(
        signingKey: 'test',
        snapshot: snapshot,
      );
      expect(result.failure?.message, contains('classification_index_out_of_bounds'));
      expect(result.validatedClassification, isNull);
      expect(prompts, hasLength(2));
    });

    test('neither step returns a public result shape', () async {
      if (!SummarizeDiagnosticMap.armed) {
        return;
      }
      final processor = _scripted([_factsOnlyJson, _validClassification], []);
      final extraction = await processor.runIsolatedMapEvidenceDiagnostic(
        signingKey: 'test',
        promptVariant: SummarizeMapPromptVariant.factsOnly,
      );
      expect(extraction.validatedEvidence?.containsKey('summary'), isFalse);
      final result = await processor.runFactsOnlyClassificationDiagnostic(
        signingKey: 'test',
        snapshot: extraction.factsSnapshot!,
      );
      expect(
        result.validatedClassification?.keys.toSet(),
        {'schemaVersion', 'priority', 'openItems'},
      );
    });
  });
}
