import 'package:edgemint_worker/contracts/worker_task_request.dart';
import 'package:edgemint_worker/contracts/worker_task_result.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/runtime/gemma_generation_output_limit.dart';
import 'package:edgemint_worker/tasks/handlers/direct_prompt_handler.dart';
import 'package:edgemint_worker/telemetry/worker_task_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GemmaGenerationOutputLimit', () {
    test('text.direct default is 512 and is separate from context 2048', () {
      expect(
        GemmaGenerationOutputLimit.forTextDirect(prompt: 'Say hello'),
        512,
      );
      expect(GemmaGenerationOutputLimit.textDirect, isNot(2048));
    });

    test('long-form text.direct uses 1024', () {
      expect(
        GemmaGenerationOutputLimit.forTextDirect(
          prompt: 'Write a 5-page article about harbor logistics.',
        ),
        GemmaGenerationOutputLimit.textDirectLongForm,
      );
      expect(
        GemmaGenerationOutputLimit.forTextDirect(
          prompt: 'Hello',
          longForm: true,
        ),
        1024,
      );
    });

    test('Persian 5-page article resolves to 1024 even when manifest sends legacy 256', () {
      const prompt = 'یه مقاله در مورد مورچه بده که ۵ صفحه بشه';
      final decision = GemmaGenerationOutputLimit.resolveTextDirect(
        prompt: prompt,
        explicitMaxOutputTokens: 256,
        maxOutputTokensSpecified: true,
      );

      expect(decision.detectedLongForm, isTrue);
      expect(decision.requestedOutputLimit, 1024);
      expect(decision.effectiveOutputLimit, 1024);
      expect(decision.source, 'long-form');
      expect(
        GemmaGenerationOutputLimit.forTextDirect(prompt: prompt),
        1024,
      );
    });

    test('explicit maxOutputTokens other than legacy 256 overrides long-form', () {
      final decision = GemmaGenerationOutputLimit.resolveTextDirect(
        prompt: 'یه مقاله در مورد مورچه بده که ۵ صفحه بشه',
        explicitMaxOutputTokens: 768,
        maxOutputTokensSpecified: true,
      );

      expect(decision.detectedLongForm, isTrue);
      expect(decision.requestedOutputLimit, 1024);
      expect(decision.effectiveOutputLimit, 768);
      expect(decision.source, 'explicit');
    });

    test('normal text.direct stays 512 when the manifest still carries 256', () {
      final decision = GemmaGenerationOutputLimit.resolveTextDirect(
        prompt: 'Say hello',
        explicitMaxOutputTokens: 256,
        maxOutputTokensSpecified: true,
      );

      expect(decision.detectedLongForm, isFalse);
      expect(decision.effectiveOutputLimit, 512);
      expect(decision.source, 'default');
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
    test('output-limit evidence is not a successful result', () {
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

      expect(result.status, WorkerResultStatus.failed);
      expect(result.output?['truncated'], isTrue);
      expect(result.output?['stopReason'], 'OUTPUT_LIMIT');
      expect(result.output?['generatedChunks'], 256);
      expect(result.error?.retryable, isFalse);
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
}

String _piece(int index) {
  final a = String.fromCharCode(97 + (index % 26));
  final b = String.fromCharCode(97 + ((index ~/ 26) % 26));
  return '$a$b';
}

WorkerTaskRequest _request({bool allowTruncatedOutput = false}) {
  return WorkerTaskRequest(
    schemaVersion: '1.0',
    taskId: 'tsk-direct',
    idempotencyKey: 'idem',
    type: 'text.direct.v1',
    input: const WorkerTaskInput(text: 'Write a 5-page article'),
    options: WorkerTaskOptions(allowTruncatedOutput: allowTruncatedOutput),
  );
}
