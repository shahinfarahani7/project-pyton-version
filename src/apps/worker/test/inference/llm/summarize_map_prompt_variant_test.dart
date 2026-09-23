// NOT RUN — evidence-v2 and armed-diagnostic cases require:
// flutter test test/inference/llm/summarize_map_prompt_variant_test.dart
//   --dart-define=SUMMARIZE_EVIDENCE_V2=true
//   --dart-define=SUMMARIZE_DIAGNOSTIC_MAP_EVIDENCE=true

import 'package:edgemint_worker/contracts/worker_error.dart';
import 'package:edgemint_worker/inference/llm/diagnostic/summarize_map_evidence_diagnostic_fixture.dart';
import 'package:edgemint_worker/inference/llm/diagnostic/summarize_map_prompt_variant.dart';
import 'package:edgemint_worker/inference/llm/prompt_templates.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/llm/summarize_diagnostic_map.dart';
import 'package:edgemint_worker/inference/llm/summarize_evidence_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

const _currentRepeatRule =
    '  string. Split unrelated events or decisions into separate entries. Do not repeat\n'
    '  the same fact in different wording.';

const _explicitRepeatRule =
    '  string. Split unrelated events or decisions into separate entries. Do not restate\n'
    '  an unchanged status in different wording; a later explicit update to the same\n'
    '  event is a separate fact (see field assignment).';

const _currentFieldRules =
    '- Short faithful quotations are allowed for exact attribution or priority; do not\n'
    '  copy paragraph-length text into one string.\n'
    '- openItems: one concise string per unresolved question in this chunk only; state\n'
    '  resolutions as facts instead. [] if none.\n'
    '- priority: concise paraphrase or short quotation of explicit customer priority;\n'
    '  otherwise "".';

const _explicitFieldRules =
    '- Field assignment — assign statements by their role as follows:\n'
    '  facts: events, amounts, statuses, and attribution (who claimed, denied, or\n'
    '  provided evidence). When the source gives a later explicit update to the same\n'
    '  event (promised then received with stated timing, pending then released or\n'
    '  completed, offered then declined with reason), record that update as its own\n'
    '  fact; it is not a redundant repeat of the earlier status.\n'
    '  openItems: only what the source itself still leaves unresolved or unexplained;\n'
    '  do not infer an open question from an event the source already resolves. [] if none.\n'
    "  priority: the customer's explicitly stated main concern, paraphrase or short\n"
    '  quotation; put that concern here only — do not restate the same concern sentence\n'
    '  in facts[]. Keep in facts the specific events, claims, denials, and records\n'
    '  that support the concern. "" if none.\n'
    '- Customer instructions below that mention mainComplaint or missingOrUnclear apply\n'
    '  at this Map stage as priority and openItems; leave that instruction text verbatim.\n'
    '- Short faithful quotations are allowed for exact attribution or priority; do not\n'
    '  copy paragraph-length text into one string.';

const _fieldMappingRule =
    '- Customer instructions below that mention mainComplaint or missingOrUnclear apply\n'
    '  at this Map stage as priority and openItems; leave that instruction text verbatim.';

const _noFieldMappingRule =
    "- Use the customer's instructions to identify relevant evidence. Field values\n"
    '  must describe the source content, not name output fields. Put the stated\n'
    '  main concern in priority and explicitly unresolved matters in openItems.';

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

void main() {
  group('Map prompt variant parsing', () {
    test('accepts current and explicit_updates only', () {
      expect(
        parseSummarizeMapPromptVariant('current'),
        SummarizeMapPromptVariant.current,
      );
      expect(
        parseSummarizeMapPromptVariant('explicit_updates'),
        SummarizeMapPromptVariant.explicitUpdates,
      );
      expect(
        parseSummarizeMapPromptVariant('explicit_updates_no_field_mapping'),
        SummarizeMapPromptVariant.explicitUpdatesNoFieldMapping,
      );
      for (final invalid in ['', 'explicitUpdates', 'CURRENT', 'v2']) {
        expect(
          () => parseSummarizeMapPromptVariant(invalid),
          throwsA(isA<WorkerError>()),
        );
      }
    });

    test('default configuration is current', () {
      const raw = String.fromEnvironment(
        summarizeMapPromptVariantConfigurationName,
      );
      if (raw.isNotEmpty) {
        return;
      }
      expect(SummarizeDiagnosticMap.promptVariant, SummarizeMapPromptVariant.current);
    });
  });

  group('Map prompt variant rendering (NOT RUN by default)', () {
    for (final fixture in SummarizeMapEvidenceDiagnosticFixtureId.values) {
      test('current preserves production prompt (${fixture.logLabel})', () {
        if (!SummarizeEvidencePipeline.enabled) {
          return;
        }
        final production = PromptTemplates.summarizeMapChunk(
          chunkText: sourceForMapEvidenceDiagnosticFixture(fixture),
          chunkIndex: 0,
          totalChunks: 1,
          chunkId: 'a' * 64,
          userInstructions: summarizeMapEvidenceDiagnosticInstructions,
          constraints: summarizeMapEvidenceDiagnosticConstraints(),
        );
        expect(_render(SummarizeMapPromptVariant.current, fixture), production);
        expect(production, contains(_currentRepeatRule));
        expect(production, contains(_currentFieldRules));
      });

      test('explicit_updates changes only approved blocks (${fixture.logLabel})', () {
        if (!SummarizeEvidencePipeline.enabled) {
          return;
        }
        final current = _render(SummarizeMapPromptVariant.current, fixture);
        final explicit =
            _render(SummarizeMapPromptVariant.explicitUpdates, fixture);
        expect(explicit, contains(_explicitRepeatRule));
        expect(explicit, contains(_explicitFieldRules));
        expect(explicit, isNot(contains(_currentFieldRules)));
        final restored = explicit
            .replaceFirst(_explicitRepeatRule, _currentRepeatRule)
            .replaceFirst(_explicitFieldRules, _currentFieldRules);
        expect(restored, current);
      });

      test('explicit_updates_no_field_mapping differs only in mapping bullet (${fixture.logLabel})', () {
        if (!SummarizeEvidencePipeline.enabled) {
          return;
        }
        final explicit =
            _render(SummarizeMapPromptVariant.explicitUpdates, fixture);
        final noMapping = _render(
          SummarizeMapPromptVariant.explicitUpdatesNoFieldMapping,
          fixture,
        );
        expect(explicit, contains(_fieldMappingRule));
        expect(noMapping, contains(_noFieldMappingRule));
        expect(noMapping, isNot(contains(_fieldMappingRule)));
        expect(
          noMapping.replaceFirst(_noFieldMappingRule, _fieldMappingRule),
          explicit,
        );
        expect(noMapping, contains(summarizeMapEvidenceDiagnosticInstructions));
        expect(
          noMapping,
          contains(
            'Chunk text:\n---\n${sourceForMapEvidenceDiagnosticFixture(fixture)}\n---',
          ),
        );
      });

      test('full fixture and verbatim instructions in explicit_updates (${fixture.logLabel})', () {
        if (!SummarizeEvidencePipeline.enabled) {
          return;
        }
        final explicit =
            _render(SummarizeMapPromptVariant.explicitUpdates, fixture);
        final source = sourceForMapEvidenceDiagnosticFixture(fixture);
        expect(explicit, contains('Chunk text:\n---\n$source\n---'));
        expect(explicit, contains(summarizeMapEvidenceDiagnosticInstructions));
        expect(explicit, contains('Soft JSON size target: about'));
      });
    }

    test('production summarizeMapChunk never renders explicit_updates text', () {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      final production = PromptTemplates.summarizeMapChunk(
        chunkText: 'Sample chunk body.',
        chunkIndex: 0,
        totalChunks: 2,
        chunkId: 'b' * 64,
        userInstructions: summarizeMapEvidenceDiagnosticInstructions,
        constraints: summarizeMapEvidenceDiagnosticConstraints(),
      );
      expect(production, isNot(contains('Field assignment')));
      expect(production, isNot(contains('see field assignment')));
      expect(production, isNot(contains('not name output fields')));
    });
  });

  group('Diagnostic explicit_updates validation (NOT RUN by default)', () {
    test('diagnostic sends explicit_updates prompt and logs variant', () async {
      if (!SummarizeDiagnosticMap.armed) {
        return;
      }
      final logs = <String>[];
      final prompts = <String>[];
      final processor = QwenTaskProcessor(
        log: logs.add,
        runner: (prompt) async {
          prompts.add(prompt);
          return '{"schemaVersion":"2","facts":["R201 late."],"openItems":[],'
              '"priority":""}';
        },
      );
      final result = await processor.runIsolatedMapEvidenceDiagnostic(
        signingKey: 'test',
        fixtureId: SummarizeMapEvidenceDiagnosticFixtureId.narrative,
        promptVariant: SummarizeMapPromptVariant.explicitUpdates,
      );
      expect(prompts.first, contains(_explicitFieldRules));
      expect(result.promptVariant, SummarizeMapPromptVariant.explicitUpdates);
      expect(result.promptSha256, hasLength(64));
      expect(
        logs.any((line) =>
            line.contains('variant=explicit_updates') &&
            line.contains('fullSourceInMapBody=true')),
        isTrue,
      );
    });

    test('duplicate priority still rejected under explicit_updates', () async {
      if (!SummarizeDiagnosticMap.armed) {
        return;
      }
      final processor = QwenTaskProcessor(
        runner: (_) async =>
            '{"schemaVersion":"2","facts":["Main concern X."],"openItems":[],'
            '"priority":"Main concern X."}',
      );
      final result = await processor.runIsolatedMapEvidenceDiagnostic(
        signingKey: 'test',
        promptVariant: SummarizeMapPromptVariant.explicitUpdates,
      );
      expect(result.validatedEvidence, isNull);
      expect(result.failure, isNotNull);
      expect(result.firstPassSuccess, isFalse);
      expect(result.repairedSuccess, isFalse);
      expect(result.correctiveInferenceCalls, lessThanOrEqualTo(1));
    });

    test('truncation still fails strict validation under explicit_updates', () async {
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
        promptVariant: SummarizeMapPromptVariant.explicitUpdates,
      );
      expect(result.truncated, isTrue);
      expect(result.validatedEvidence, isNull);
      expect(result.firstPassSuccess, isFalse);
    });
  });
}
