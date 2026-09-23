// NOT RUN — compile-flag and live-inference cases require dart-defines / device.

import 'package:edgemint_worker/contracts/worker_error.dart';
import 'package:edgemint_worker/inference/llm/diagnostic/summarize_map_evidence_diagnostic_fixture.dart';
import 'package:edgemint_worker/inference/llm/hierarchical_summarize_pipeline.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/llm/summarize_diagnostic_map.dart';
import 'package:edgemint_worker/inference/llm/summarize_evidence_pipeline.dart';
import 'package:edgemint_worker/inference/llm/summarize_inference_stage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SummarizeDiagnosticMap (NOT RUN by default)', () {
    test('flag off keeps diagnostic disarmed', () {
      if (SummarizeDiagnosticMap.requested) {
        return;
      }
      expect(SummarizeDiagnosticMap.armed, isFalse);
      expect(
        () => SummarizeDiagnosticMap.assertArmedOrThrow(),
        throwsA(isA<WorkerError>()),
      );
    });

    test('diagnostic requires evidence v2 compile flag', () {
      if (SummarizeEvidencePipeline.enabled) {
        return;
      }
      expect(
        () => SummarizeDiagnosticMap.assertArmedOrThrow(),
        throwsA(isA<WorkerError>()),
      );
    });

    test('isolated diagnostic rejects when not armed', () async {
      if (SummarizeDiagnosticMap.armed) {
        return;
      }
      final processor = QwenTaskProcessor(
        runner: (_) async => '{"schemaVersion":"2","facts":[],"openItems":[],"priority":""}',
      );
      expect(
        () => processor.runIsolatedMapEvidenceDiagnostic(signingKey: 'test'),
        throwsA(isA<WorkerError>()),
      );
    });

    test('isolated diagnostic invokes mapEvidence not directPublic', () async {
      if (!SummarizeDiagnosticMap.armed) {
        return;
      }
      final processor = QwenTaskProcessor(
        runner: (prompt) async {
          expect(prompt, contains('Extract evidence'));
          expect(prompt, contains('Chunk text:'));
          expect(prompt, contains('Order R201'));
          return '{"schemaVersion":"2","facts":["Order R201 arrived late."],'
              '"openItems":[],"priority":"substitution"}';
        },
      );
      final result = await processor.runIsolatedMapEvidenceDiagnostic(
        signingKey: 'test',
        runId: 'test_run_map_evidence',
      );
      expect(result.inferenceStage, 'mapEvidence');
      expect(result.runId, 'test_run_map_evidence');
      expect(result.normalInferenceCalls, 1);
      expect(result.fixtureId, SummarizeMapEvidenceDiagnosticFixtureId.baselineFactLines);
      expect(result.validatedEvidence, isNotNull);
    });

    test('narrative fixture runs through same mapEvidence entrypoint', () async {
      if (!SummarizeDiagnosticMap.armed) {
        return;
      }
      final narrativeSource = sourceForMapEvidenceDiagnosticFixture(
        SummarizeMapEvidenceDiagnosticFixtureId.narrative,
      );
      final processor = QwenTaskProcessor(
        runner: (prompt) async {
          expect(prompt, contains('I am contacting you about three orders'));
          expect(prompt, contains('The cause remains unexplained.'));
          return '{"schemaVersion":"2","facts":["R201 late"],"openItems":[],'
              '"priority":""}';
        },
      );
      final result = await processor.runIsolatedMapEvidenceDiagnostic(
        signingKey: 'test',
        fixtureId: SummarizeMapEvidenceDiagnosticFixtureId.narrative,
      );
      expect(result.fixtureId, SummarizeMapEvidenceDiagnosticFixtureId.narrative);
      expect(result.sourceChars, narrativeSource.replaceAll('\r\n', '\n').length);
    });

    test('diagnostic rejects multi-chunk plan before Map inference', () async {
      if (!SummarizeDiagnosticMap.armed) {
        return;
      }
      final processor = QwenTaskProcessor();
      final plan = processor.planInputChunks(
        summarizeMapEvidenceDiagnosticSourceBaseline,
        experimentalSourceChunkTokenCap: 200,
      );
      if (plan.totalChunks <= 1) {
        return;
      }
      expect(
        () => processor.runIsolatedMapEvidenceDiagnostic(
          signingKey: 'test',
          fixtureId: SummarizeMapEvidenceDiagnosticFixtureId.baselineFactLines,
        ),
        throwsA(isA<WorkerError>()),
      );
    });

    test('baseline and narrative fixture sources differ', () {
      expect(
        summarizeMapEvidenceDiagnosticSourceBaseline.trim(),
        isNot(equals(summarizeMapEvidenceDiagnosticSourceNarrative.trim())),
      );
    });

    test('single chunk production summarize still routes directPublic', () async {
      final processor = QwenTaskProcessor();
      final plan = processor.planInputChunks(
        summarizeMapEvidenceDiagnosticSourceBaseline,
      );
      expect(plan.totalChunks, 1);

      final stages = <SummarizeInferenceStage>[];
      final pipeline = HierarchicalSummarizePipeline(
        contextBudget: processor.contextBudget,
        runPromptJson: (prompt, {required SummarizeInferenceStage inferenceStage}) async {
          stages.add(inferenceStage);
          return const {
            'summary': 'x',
            'keyPoints': ['a'],
            'mainComplaint': 'c',
            'suggestedImprovement': 'i',
            'missingOrUnclear': [],
          };
        },
      );

      await pipeline.summarize(
        inputText: summarizeMapEvidenceDiagnosticSourceBaseline,
        plan: plan,
      );

      expect(stages, hasLength(1));
      expect(stages.single, SummarizeInferenceStage.directPublic);
    });

    test('diagnostic does not return public five-field schema shape', () async {
      if (!SummarizeDiagnosticMap.armed) {
        return;
      }
      final processor = QwenTaskProcessor(
        runner: (_) async =>
            '{"schemaVersion":"2","facts":["fact"],"openItems":[],"priority":""}',
      );
      final result = await processor.runIsolatedMapEvidenceDiagnostic(
        signingKey: 'test',
      );
      expect(result.validatedEvidence?.containsKey('summary'), isFalse);
      expect(result.validatedEvidence?['schemaVersion'], '2');
    });

    test('truncated map evidence fails strict validation in diagnostic', () async {
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
      );
      expect(result.failure, isNotNull);
      expect(result.truncated, isTrue);
      expect(result.validatedEvidence, isNull);
      expect(result.firstPassSuccess, isFalse);
    });
  });
}
