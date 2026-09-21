import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:edgemint_worker/contracts/worker_error.dart';
import 'package:edgemint_worker/inference/llm/prompt_templates.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/validation/json_output_validator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/task_e98fbaac_map_response.dart';

void main() {
  group('task tsk_dev_e98fbaac map response (live log 20260921-084119)', () {
    test('fixture length matches INFERENCE RESPONSE map metadata', () {
      expect(taskE98fbaacMapResponseRaw.length, taskE98fbaacLogChars);
      expect(
        utf8.encode(taskE98fbaacMapResponseRaw).length,
        taskE98fbaacLogUtf8Bytes,
      );
    });

    test('legacy strip left malformed fence backtick on cleaned body', () {
      final legacy = taskE98fbaacLegacyStrip(taskE98fbaacMapResponseRaw);
      expect(legacy.endsWith('`'), isTrue);
      expect(
        () => jsonDecode(legacy),
        throwsA(isA<FormatException>()),
        reason: 'decode at line 8 char 1 backtick',
      );
    });

    test('current extractor decodes real response without corrective call', () {
      final extract = JsonOutputValidator.extractJsonObject(
        taskE98fbaacMapResponseRaw,
      );

      expect(extract.ok, isTrue, reason: extract.rejectionReason);
      expect(extract.rejectionReason, isNull);
      expect(
        (extract.object!['keyPoints'] as List).length,
        taskE98fbaacExpectedKeyPointCount,
      );
      expect(
        extract.object!['summary'],
        contains('incorrect substitution'),
      );
    });

    test('extracts when opening brace sits on the markdown fence line', () {
      expect(
        taskE98fbaacMapResponseBraceOnFenceLine.length,
        taskE98fbaacLogChars,
      );
      final extract = JsonOutputValidator.extractJsonObject(
        taskE98fbaacMapResponseBraceOnFenceLine,
      );
      expect(extract.ok, isTrue, reason: extract.rejectionReason);
      expect(extract.rejectionStage, isNull);
    });

    test('map runJsonTask parses brace-on-fence response without repair', () async {
      var calls = 0;
      final logs = <String>[];
      final processor = QwenTaskProcessor(
        log: logs.add,
        runner: (prompt) async {
          calls += 1;
          return taskE98fbaacMapResponseBraceOnFenceLine;
        },
      );

      final result = await processor.runJsonTask(
        prompt: PromptTemplates.summarizeMapChunk(
          chunkText: 'Order B410 arrived late; order B426 had wrong milk.',
          chunkIndex: 0,
          totalChunks: 2,
          chunkId: 'c' * 64,
        ),
        signingKey: 'sign',
        correctiveBudget: CorrectiveInferenceBudget(),
      );

      expect(calls, 1);
      expect(
        logs.any((line) => line.contains('[JSON EXTRACT REJECTED]')),
        isFalse,
      );
      expect(
        logs.any((line) => line.contains('[JSON CORRECTIVE]')),
        isFalse,
      );
      expect(
        (result['keyPoints'] as List).length,
        taskE98fbaacExpectedKeyPointCount,
      );
    });

    test('map runJsonTask parses locally without labeled fallback', () async {
      var calls = 0;
      final prompts = <String>[];
      final logs = <String>[];
      final processor = QwenTaskProcessor(
        log: logs.add,
        runner: (prompt) async {
          calls += 1;
          prompts.add(prompt);
          return taskE98fbaacMapResponseRaw;
        },
      );

      final result = await processor.runJsonTask(
        prompt: PromptTemplates.summarizeMapChunk(
          chunkText: 'Order B410 arrived late; order B426 had wrong milk.',
          chunkIndex: 0,
          totalChunks: 2,
          chunkId: 'c' * 64,
        ),
        signingKey: 'sign',
        labeledFallback: true,
        correctiveBudget: CorrectiveInferenceBudget(),
      );

      expect(calls, 1);
      expect(
        prompts.where((prompt) => prompt.contains('Answer in plain lines')),
        isEmpty,
      );
      expect(
        logs.any((line) => line.contains('[JSON EXTRACT REJECTED]')),
        isFalse,
      );
      expect(
        (result['keyPoints'] as List).length,
        taskE98fbaacExpectedKeyPointCount,
      );
    });

    test('reports SHA-256 transcription gap against device log metadata', () {
      final sha = sha256.convert(utf8.encode(taskE98fbaacMapResponseRaw));
      expect(sha.toString(), isNot(taskE98fbaacLogSha256));
      expect(
        JsonOutputValidator.extractJsonObject(taskE98fbaacMapResponseRaw).ok,
        isTrue,
      );
      expect(
        JsonOutputValidator.extractJsonObject(
          taskE98fbaacMapResponseBraceOnFenceLine,
        ).ok,
        isTrue,
      );
    });

    test('reports decode failure accurately when JSON stays unusable', () async {
      var calls = 0;
      final processor = QwenTaskProcessor(
        runner: (prompt) async {
          calls += 1;
          if (prompt.contains('Chunk metadata:')) {
            return '```json\nThis is prose, not JSON at all.\n``';
          }
          if (prompt.contains('Fix the following broken JSON')) {
            return 'still not json at all';
          }
          return '{}';
        },
      );

      await expectLater(
        processor.runSummarizeJsonTask(
          inputText: '${'Chunk body. ' * 900}\n\n${'Tail. ' * 300}',
          signingKey: 'sign',
        ),
        throwsA(
          isA<WorkerError>()
              .having(
                (error) => error.code,
                'code',
                WorkerErrorCode.llmInvalidJson,
              )
              .having((error) => error.retryable, 'retryable', isFalse)
              .having(
                (error) => error.message,
                'message',
                contains('reason='),
              ),
        ),
      );
      expect(calls, lessThanOrEqualTo(3));
      expect(calls, greaterThan(1));
    });
  });
}
