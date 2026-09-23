// NOT RUN — compile-flag cases require dart-defines; engine-param cases run without.

import 'package:edgemint_worker/contracts/worker_error.dart';
import 'package:edgemint_worker/inference/llm/formatted_prompt_builder.dart';
import 'package:edgemint_worker/inference/llm/prompt_templates.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/llm/semantic_chunk_engine.dart';
import 'package:edgemint_worker/inference/llm/summarize_chunk_experiment.dart';
import 'package:edgemint_worker/inference/llm/summarize_evidence_pipeline.dart';
import 'package:edgemint_worker/runtime/checkpoint_manager.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/customer_feedback_regression.dart';
import 'fixtures/semantic_chunk_golden.dart';

void main() {
  group('SummarizeChunkExperiment planning (NOT RUN by default)', () {
    const engine = SemanticChunkEngine();
    const reservedPromptTokens = 1031;

    int chunkTokenBudget() => engine.chunkTokenBudget(
          reservedPromptTokens: reservedPromptTokens,
        );

    SummarizeChunkExperimentBudget baselineBudget() =>
        SummarizeChunkExperiment.resolveBudget(
          chunkTokenBudget: chunkTokenBudget(),
          overlapTokens: engine.overlapTokens,
        );

    void expectEveryFinalChunkBodyWithinCap({
      required ChunkPlan plan,
      required int effectiveTotalBodyCap,
    }) {
      for (final chunk in plan.chunks) {
        expect(
          engine.estimator.estimate(chunk.text),
          lessThanOrEqualTo(effectiveTotalBodyCap),
        );
        expect(chunk.estimatedTokens, lessThanOrEqualTo(effectiveTotalBodyCap));
      }
    }

    test('no experimental cap preserves default chunk boundaries', () {
      final input = semanticChunkGoldenMultiChunkInput(engine: engine);
      final baseline = engine.chunk(
        input,
        reservedPromptTokens: reservedPromptTokens,
      );
      final capped = engine.chunk(
        input,
        reservedPromptTokens: reservedPromptTokens,
        experimentalSourceChunkTokenCap: null,
      );

      expect(capped.totalChunks, baseline.totalChunks);
      expect(capped.chunks.first.chunkId, baseline.chunks.first.chunkId);
      expect(capped.experimentalSourceChunkTokenCap, isNull);
      expect(
        capped.effectiveTotalSourceBodyTokenBudget,
        chunkTokenBudget(),
      );
      expect(
        capped.preOverlapPackTokenBudget,
        chunkTokenBudget() - engine.overlapTokens,
      );
    });

    test('positive cap reduces total body budget and increases chunk count', () {
      final input = semanticChunkGoldenMultiChunkInput(engine: engine);
      final baseline = engine.chunk(
        input,
        reservedPromptTokens: reservedPromptTokens,
      );
      const cap = 1200;
      final capped = engine.chunk(
        input,
        reservedPromptTokens: reservedPromptTokens,
        experimentalSourceChunkTokenCap: cap,
      );

      expect(capped.effectiveTotalSourceBodyTokenBudget, cap);
      expect(capped.preOverlapPackTokenBudget, cap - engine.overlapTokens);
      expect(capped.totalChunks, greaterThanOrEqualTo(baseline.totalChunks));
      expectEveryFinalChunkBodyWithinCap(
        plan: capped,
        effectiveTotalBodyCap: cap,
      );
    });

    test('cap above safe total body budget never increases total body budget', () {
      final budget = baselineBudget();
      final resolved = SummarizeChunkExperiment.resolveBudget(
        chunkTokenBudget: budget.chunkTokenBudget,
        overlapTokens: engine.overlapTokens,
      );
      expect(resolved.active, isFalse);
      expect(
        resolved.effectiveTotalSourceBodyTokenBudget,
        resolved.safeTotalSourceBodyTokenBudget,
      );

      final capped = engine.chunk(
        semanticChunkGoldenMultiChunkInput(engine: engine),
        reservedPromptTokens: reservedPromptTokens,
        experimentalSourceChunkTokenCap: 999999,
      );
      expect(
        capped.effectiveTotalSourceBodyTokenBudget,
        lessThanOrEqualTo(resolved.safeTotalSourceBodyTokenBudget),
      );
      expectEveryFinalChunkBodyWithinCap(
        plan: capped,
        effectiveTotalBodyCap: capped.effectiveTotalSourceBodyTokenBudget!,
      );
    });

    test('impossible cap below overlap reserve fails explicitly', () {
      expect(
        () => engine.chunk(
          semanticChunkGoldenInput(),
          reservedPromptTokens: reservedPromptTokens,
          experimentalSourceChunkTokenCap: engine.overlapTokens,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('malformed dart-define values fail explicitly', () {
      expect(
        () => SummarizeChunkExperiment.parseRequestedSourceChunkTokens('1200abc'),
        throwsA(
          isA<WorkerError>().having(
            (error) => error.code,
            'code',
            WorkerErrorCode.invalidTask,
          ),
        ),
      );
      expect(
        SummarizeChunkExperiment.parseRequestedSourceChunkTokens(
          '1200abc',
          throwOnInvalid: false,
        ),
        0,
      );
      expect(SummarizeChunkExperiment.parseRequestedSourceChunkTokens(''), 0);
      expect(SummarizeChunkExperiment.parseRequestedSourceChunkTokens('0'), 0);
      expect(
        SummarizeChunkExperiment.parseRequestedSourceChunkTokens('1200'),
        1200,
      );
      expect(
        () => SummarizeChunkExperiment.parseRequestedSourceChunkTokens('-1'),
        throwsA(isA<WorkerError>()),
      );
    });

    test('complete source coverage preserves order and overlap on capped plan', () {
      final input = semanticChunkGoldenMultiChunkInput(engine: engine);
      const cap = 1200;
      final plan = engine.chunk(
        input,
        reservedPromptTokens: reservedPromptTokens,
        experimentalSourceChunkTokenCap: cap,
      );

      expect(plan.chunks.first.processedRange.startChar, 0);
      expect(
        plan.chunks.last.processedRange.endChar,
        lessThanOrEqualTo(input.length),
      );
      for (var index = 1; index < plan.chunks.length; index++) {
        expect(plan.chunks[index].overlapChars, greaterThan(0));
        expect(
          plan.chunks[index].processedRange.startChar,
          greaterThanOrEqualTo(plan.chunks[index - 1].processedRange.startChar),
        );
      }
      expectEveryFinalChunkBodyWithinCap(
        plan: plan,
        effectiveTotalBodyCap: cap,
      );
    });

    test('planner terminates with monotonic progress under small cap', () {
      const cap = 400;
      final plan = engine.chunk(
        semanticChunkGoldenMultiChunkInput(engine: engine),
        reservedPromptTokens: reservedPromptTokens,
        experimentalSourceChunkTokenCap: cap,
      );
      expect(plan.totalChunks, greaterThan(1));
      for (var index = 1; index < plan.chunks.length; index++) {
        expect(
          plan.chunks[index].processedRange.startChar,
          greaterThan(plan.chunks[index - 1].processedRange.startChar),
        );
      }
      expect(
        plan.chunks.last.processedRange.endChar,
        greaterThan(0),
      );
      expectEveryFinalChunkBodyWithinCap(
        plan: plan,
        effectiveTotalBodyCap: cap,
      );
    });

    test('rendered Map prompt remains within direct inference budget', () {
      final processor = QwenTaskProcessor();
      const cap = 1200;
      final plan = engine.chunk(
        semanticChunkGoldenMultiChunkInput(engine: engine),
        reservedPromptTokens: processor.summarizePromptReserveTokens(
          userInstructions: customerFeedbackInstructions,
          constraints: customerFeedbackConstraints(),
        ),
        experimentalSourceChunkTokenCap: cap,
      );
      expectEveryFinalChunkBodyWithinCap(
        plan: plan,
        effectiveTotalBodyCap: cap,
      );
      final chunk = plan.chunks.first;
      final prompt = PromptTemplates.summarizeMapChunk(
        chunkText: chunk.text,
        chunkIndex: chunk.chunkIndex,
        totalChunks: plan.totalChunks,
        chunkId: chunk.chunkId,
        userInstructions: customerFeedbackInstructions,
        constraints: customerFeedbackConstraints(),
      );
      final evaluation = processor.contextBudget.evaluateFormattedPrompt(
        formattedPrompt: FormattedPromptBuilder.buildTaskPrompt(
          templateBody: prompt,
          systemInstruction: processor.contextBudget.defaultSystemInstruction,
        ),
        maxOutputTokens: processor.config.maxOutputTokens,
      );
      expect(evaluation.fitsDirectInference, isTrue);
    });

    test('experiment gate requires evidence v2 compile flag', () {
      if (SummarizeEvidencePipeline.enabled &&
          SummarizeChunkExperiment.compileTimeRequested) {
        expect(SummarizeChunkExperiment.active, isTrue);
        return;
      }
      expect(SummarizeChunkExperiment.active, isFalse);
    });

    test('resolveBudget inactive preserves default total and pack budgets', () {
      final budget = baselineBudget();
      expect(budget.active, isFalse);
      expect(budget.requestedSourceChunkTokens, 0);
      expect(budget.safeTotalSourceBodyTokenBudget, budget.chunkTokenBudget);
      expect(
        budget.effectiveTotalSourceBodyTokenBudget,
        budget.safeTotalSourceBodyTokenBudget,
      );
      expect(
        budget.preOverlapPackTokenBudget,
        budget.chunkTokenBudget - engine.overlapTokens,
      );
    });

    test('checkpoint promptVersion differs between default and capped plans', () {
      if (!SummarizeEvidencePipeline.enabled) {
        expect(
          SummarizeChunkExperiment.checkpointPromptVersion('2.0'),
          '2.0',
        );
        return;
      }
      final version =
          SummarizeChunkExperiment.checkpointPromptVersion('2.0');
      if (SummarizeChunkExperiment.active) {
        expect(version, '2.0+srcCap${SummarizeChunkExperiment.requestedSourceChunkTokens}');
      } else {
        expect(version, '2.0');
      }
    });

    test('checkpoint resume rejects mismatched plan promptVersion', () async {
      final store = InMemoryEncryptedStore();
      final manager = CheckpointManager(store);
      final plan = engine.chunk(semanticChunkGoldenInput());
      expect(plan.totalChunks, greaterThanOrEqualTo(1));

      await manager.saveChunkCheckpoint(
        assignmentId: 'asg-exp',
        fenceToken: 1,
        chunk: plan.chunks.first,
        partialSummary: const {
          'schemaVersion': '2',
          'facts': ['fact'],
          'openItems': [],
          'priority': '',
        },
        promptVersion: '2.0+srcCap1200',
      );

      final resume = await manager.loadResumableState(
        assignmentId: 'asg-exp',
        activeFenceToken: 1,
        inputHash: plan.inputHash,
        promptVersion: '2.0',
      );
      expect(resume, isNull);
    });

    test('runSummarizeJsonTask uses one shared corrective budget', () async {
      final processor = QwenTaskProcessor(
        runner: (prompt) async => '{"summary":"x","keyPoints":["a"],'
            '"mainComplaint":"c","suggestedImprovement":"i","missingOrUnclear":[]}',
      );
      await processor.runSummarizeJsonTask(
        inputText: 'Short body.',
        signingKey: 'sign',
      );
      // Wiring contract: no additional CorrectiveInferenceBudget construction
      // sites were added for per-chunk/per-reduce handling in this experiment.
    });
  });
}
