import 'package:edgemint_worker/contracts/worker_task_request.dart';
import 'package:edgemint_worker/contracts/worker_task_result.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/runtime/gemma_generation_output_limit.dart';
import 'package:edgemint_worker/tasks/handlers/direct_prompt_handler.dart';
import 'package:edgemint_worker/telemetry/worker_task_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GemmaGenerationOutputLimit', () {
    test('text.direct default is 256 and is separate from context 2048', () {
      expect(
        GemmaGenerationOutputLimit.forTextDirect(prompt: 'Say hello'),
        256,
      );
      expect(GemmaGenerationOutputLimit.textDirect, 256);
      expect(GemmaGenerationOutputLimit.textDirect, isNot(2048));
      expect(GemmaGenerationOutputLimit.textDirect, isNot(512));
    });

    test('medium detail is 384 and explicitly extended is 512', () {
      expect(
        GemmaGenerationOutputLimit.forTextDirect(
          prompt: 'Explain how ants farm aphids.',
        ),
        384,
      );
      final detailed = GemmaGenerationOutputLimit.resolveTextDirect(
        prompt: 'Give a very detailed extended answer about ants.',
      );
      expect(detailed.answerClass, 'detailed');
      expect(detailed.effectiveOutputLimit, 512);
      expect(detailed.staged, isFalse);
    });

    test('long-form is staged at 256 per session, not one 1024 session', () {
      final decision = GemmaGenerationOutputLimit.resolveTextDirect(
        prompt: 'Write a 5-page article about harbor logistics.',
      );
      expect(decision.answerClass, 'long-form');
      expect(decision.staged, isTrue);
      expect(decision.effectiveOutputLimit, 256);
      expect(decision.effectiveOutputLimit, isNot(1024));
      expect(
        GemmaGenerationOutputLimit.forTextDirect(
          prompt: 'Hello',
          longForm: true,
        ),
        256,
      );
    });

    test('Persian example about ants is short, not long-form', () {
      const prompt = 'در مورد پرورش مورچه یه مثاله بهم بده';
      final decision = GemmaGenerationOutputLimit.resolveTextDirect(
        prompt: prompt,
        explicitMaxOutputTokens: 256,
        maxOutputTokensSpecified: true,
      );

      expect(decision.answerClass, 'short');
      expect(decision.detectedLongForm, isFalse);
      expect(decision.staged, isFalse);
      expect(decision.effectiveOutputLimit, 256);
      expect(decision.effectiveOutputLimit, isNot(512));
      expect(decision.effectiveOutputLimit, isNot(1024));
      expect(
        GemmaGenerationOutputLimit.forTextDirect(prompt: prompt),
        256,
      );
    });

    test('Persian 5-page article is staged long-form even when manifest sends legacy 256', () {
      const prompt = 'یه مقاله در مورد مورچه بده که ۵ صفحه بشه';
      final decision = GemmaGenerationOutputLimit.resolveTextDirect(
        prompt: prompt,
        explicitMaxOutputTokens: 256,
        maxOutputTokensSpecified: true,
      );

      expect(decision.answerClass, 'long-form');
      expect(decision.detectedLongForm, isTrue);
      expect(decision.requestedOutputLimit, 256);
      expect(decision.effectiveOutputLimit, 256);
      expect(decision.staged, isTrue);
      expect(decision.source, 'long-form');
      expect(decision.effectiveOutputLimit, isNot(1024));
    });

    test('explicit maxOutputTokens other than legacy 256 overrides long-form in one session', () {
      final decision = GemmaGenerationOutputLimit.resolveTextDirect(
        prompt: 'یه مقاله در مورد مورچه بده که ۵ صفحه بشه',
        explicitMaxOutputTokens: 768,
        maxOutputTokensSpecified: true,
      );

      expect(decision.answerClass, 'long-form');
      expect(decision.requestedOutputLimit, 256);
      expect(decision.effectiveOutputLimit, 768);
      expect(decision.staged, isFalse);
      expect(decision.source, 'explicit');
    });

    test('normal text.direct stays 256 when the manifest still carries 256', () {
      final decision = GemmaGenerationOutputLimit.resolveTextDirect(
        prompt: 'Say hello',
        explicitMaxOutputTokens: 256,
        maxOutputTokensSpecified: true,
      );

      expect(decision.answerClass, 'short');
      expect(decision.detectedLongForm, isFalse);
      expect(decision.effectiveOutputLimit, 256);
      expect(decision.source, 'short');
    });
  });

  group('Gemma chunk generation', () {
    test('256 chunks at a 256 cap is OUTPUT_LIMIT, not EOS', () async {
      final pieces = List.generate(
        256,
        (index) => GemmaDecodePiece(_piece(index)),
      );
      final decode = await GemmaChunkGeneration.collect(
        pieces: Stream.fromIterable(pieces),
        configuredOutputLimit: 256,
        onStop: () async {},
      );

      expect(decode.generatedChunks, 256);
      expect(decode.stopReason, GemmaGenerationOutputLimit.outputLimit);
      expect(decode.stopReason, isNot(GemmaGenerationOutputLimit.eos));
      expect(decode.hitOutputLimit, isTrue);
      expect(decode.text, contains(_piece(0)));
      expect(decode.text, contains(_piece(255)));
    });

    test('generation longer than 256 chunks continues until the configured cap', () async {
      final pieces = List.generate(
        300,
        (index) => GemmaDecodePiece(_piece(index)),
      );
      final decode = await GemmaChunkGeneration.collect(
        pieces: Stream.fromIterable(pieces),
        configuredOutputLimit: 512,
        onStop: () async {},
      );

      expect(decode.generatedChunks, 300);
      expect(decode.generatedChunks, greaterThan(256));
      expect(decode.stopReason, GemmaGenerationOutputLimit.eos);
      expect(decode.text, contains(_piece(299)));
    });

    test('a short reply under the cap is EOS', () async {
      final decode = await GemmaChunkGeneration.collect(
        pieces: Stream.fromIterable(const [
          GemmaDecodePiece('Hello'),
          GemmaDecodePiece(' there'),
        ]),
        configuredOutputLimit: 512,
        onStop: () async {},
      );

      expect(decode.generatedChunks, 2);
      expect(decode.stopReason, GemmaGenerationOutputLimit.eos);
      expect(decode.hitOutputLimit, isFalse);
    });

    test('native end exactly at a 512 cap is OUTPUT_LIMIT', () async {
      final decode = await GemmaChunkGeneration.collect(
        pieces: Stream.fromIterable(
          List.generate(512, (index) => GemmaDecodePiece(_piece(index))),
        ),
        configuredOutputLimit: 512,
        onStop: () async {},
      );

      expect(decode.generatedChunks, 512);
      expect(decode.stopReason, GemmaGenerationOutputLimit.outputLimit);
    });
  });

  group('DirectPromptHandler truncation', () {
    test('free-form output-limit text is a truncated success', () {
      final result = DirectPromptHandler.resultFor(
        request: _request(),
        generation: const DirectGenerationReceipt(
          text: 'The article starts and then',
          stopReason: GemmaGenerationOutputLimit.outputLimit,
          configuredOutputLimit: 256,
          generatedChunks: 256,
          generatedTokens: 209,
        ),
        metrics: WorkerTaskMetrics(),
      );

      expect(result.status, WorkerResultStatus.succeeded);
      expect(result.error, isNull);
      expect(result.output?['truncated'], isTrue);
      expect(result.output?['stopReason'], 'OUTPUT_LIMIT');
      expect(result.output?['stopReason'], isNot('EOS'));
      expect(result.output?['generatedChunks'], 256);
    });

    test('empty output-limit text still fails', () {
      final result = DirectPromptHandler.resultFor(
        request: _request(),
        generation: const DirectGenerationReceipt(
          text: '   ',
          stopReason: GemmaGenerationOutputLimit.outputLimit,
          configuredOutputLimit: 256,
          generatedChunks: 256,
          generatedTokens: 0,
        ),
        metrics: WorkerTaskMetrics(),
      );

      expect(result.status, WorkerResultStatus.failed);
      expect(result.error?.code.name, 'outputSchemaMismatch');
    });

    test('structured output that hits the cap still fails', () {
      final result = DirectPromptHandler.resultFor(
        request: _request(outputSchema: const {'type': 'object'}),
        generation: const DirectGenerationReceipt(
          text: '{"summary":',
          stopReason: GemmaGenerationOutputLimit.outputLimit,
          configuredOutputLimit: 256,
          generatedChunks: 256,
          generatedTokens: 20,
        ),
        metrics: WorkerTaskMetrics(),
      );

      expect(result.status, WorkerResultStatus.failed);
      expect(result.output?['stopReason'], 'OUTPUT_LIMIT');
      expect(result.output?['truncated'], isTrue);
    });

    test('contract allowTruncatedOutput keeps the partial transcript successful', () {
      final result = DirectPromptHandler.resultFor(
        request: _request(allowTruncatedOutput: true),
        generation: const DirectGenerationReceipt(
          text: 'partial',
          stopReason: GemmaGenerationOutputLimit.outputLimit,
          configuredOutputLimit: 512,
          generatedChunks: 512,
          generatedTokens: 400,
        ),
        metrics: WorkerTaskMetrics(),
      );

      expect(result.status, WorkerResultStatus.succeeded);
      expect(result.output?['truncated'], isTrue);
    });

    test('EOS reply succeeds', () {
      final result = DirectPromptHandler.resultFor(
        request: _request(),
        generation: const DirectGenerationReceipt(
          text: 'Done.',
          stopReason: GemmaGenerationOutputLimit.eos,
          configuredOutputLimit: 512,
          generatedChunks: 4,
          generatedTokens: 2,
        ),
        metrics: WorkerTaskMetrics(),
      );

      expect(result.status, WorkerResultStatus.succeeded);
      expect(result.output?['modelTranscript'], 'Done.');
      expect(result.output?['truncated'], isFalse);
    });
  });

  group('staged long-form', () {
    test('continues in a new session after the stage cap and stops on EOS', () async {
      const prompt = 'Write a 5-page article about ants.';
      final decision = GemmaGenerationOutputLimit.resolveTextDirect(prompt: prompt);
      expect(decision.staged, isTrue);
      expect(decision.effectiveOutputLimit, 256);
      var calls = 0;
      final result = await GemmaStagedDirectGeneration.run(
        decision: decision,
        prompt: prompt,
        generateStage: (stageIndex, stagePrompt) async {
          calls += 1;
          if (stageIndex == 0) {
            expect(stagePrompt, prompt);
            return const GemmaStagePiece(
              text: 'Part one',
              stopReason: GemmaGenerationOutputLimit.outputLimit,
              generatedChunks: 256,
              generatedTokens: 200,
            );
          }
          expect(stagePrompt, contains('Continue'));
          expect(stagePrompt, isNot(prompt));
          return const GemmaStagePiece(
            text: 'Part two',
            stopReason: GemmaGenerationOutputLimit.eos,
            generatedChunks: 40,
            generatedTokens: 30,
          );
        },
      );

      expect(calls, 2);
      expect(result.text, 'Part one\nPart two');
      expect(result.stopReason, GemmaGenerationOutputLimit.eos);
      expect(result.stopReason, isNot(GemmaGenerationOutputLimit.outputLimit));
      expect(result.generatedChunks, 296);
    });

    test('a short example stays one session', () async {
      const prompt = 'در مورد پرورش مورچه یه مثاله بهم بده';
      final decision = GemmaGenerationOutputLimit.resolveTextDirect(prompt: prompt);
      var calls = 0;
      await GemmaStagedDirectGeneration.run(
        decision: decision,
        prompt: prompt,
        generateStage: (stageIndex, stagePrompt) async {
          calls += 1;
          return const GemmaStagePiece(
            text: 'example',
            stopReason: GemmaGenerationOutputLimit.eos,
            generatedChunks: 8,
            generatedTokens: 4,
          );
        },
      );
      expect(decision.answerClass, 'short');
      expect(decision.staged, isFalse);
      expect(calls, 1);
    });
  });
}

String _piece(int index) {
  final a = String.fromCharCode(97 + (index % 26));
  final b = String.fromCharCode(97 + ((index ~/ 26) % 26));
  return '$a$b';
}

WorkerTaskRequest _request({
  bool allowTruncatedOutput = false,
  Map<String, dynamic>? outputSchema,
}) {
  return WorkerTaskRequest(
    schemaVersion: '1.0',
    taskId: 'tsk-direct',
    idempotencyKey: 'idem',
    type: 'text.direct.v1',
    input: const WorkerTaskInput(text: 'Write a 5-page article'),
    options: WorkerTaskOptions(
      allowTruncatedOutput: allowTruncatedOutput,
      outputSchema: outputSchema,
    ),
  );
}
