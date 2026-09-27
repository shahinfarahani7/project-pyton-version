import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:edgemint_worker/contracts/worker_error.dart';
import 'package:edgemint_worker/inference/llm/prompt_templates.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/llm/summarize_evidence_pipeline.dart';
import 'package:edgemint_worker/inference/llm/summarize_inference_stage.dart';
import 'package:edgemint_worker/validation/json_output_validator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/task_f71a56dd_map_response.dart';

void main() {
  group('task tsk_dev_f71a56dd map response (live log 20260922-082720)', () {
    test('fixture length and SHA-256 match INFERENCE RESPONSE map metadata', () {
      expect(taskF71a56ddMapResponseRaw.length, taskF71a56ddLogChars);
      expect(
        utf8.encode(taskF71a56ddMapResponseRaw).length,
        taskF71a56ddLogUtf8Bytes,
      );
      final sha = sha256.convert(utf8.encode(taskF71a56ddMapResponseRaw));
      expect(sha.toString(), taskF71a56ddLogSha256);
    });

    test('payload uses literal escape sequences, not real newlines', () {
      expect(taskF71a56ddMapResponseRaw.contains('\n'), isFalse);
      expect(taskF71a56ddMapResponseRaw.contains(r'\n'), isTrue);
      expect(taskF71a56ddMapResponseRaw.contains(r'\"'), isTrue);
    });

    test('current extractor decodes real response without corrective call', () {
      final extract = JsonOutputValidator.extractJsonObject(
        taskF71a56ddMapResponseRaw,
      );

      expect(extract.ok, isTrue, reason: extract.rejectionReason);
      expect(extract.rejectionStage, isNull);
      expect(extract.rejectionReason, isNull);
      expect(extract.literalEscapeRecovered, isTrue);
      expect(
        (extract.object!['keyPoints'] as List).length,
        taskF71a56ddExpectedKeyPointCount,
      );
      expect(extract.object!.containsKey('summary'), isTrue);
      expect(extract.object!.containsKey('mainComplaint'), isTrue);
      expect(extract.object!.containsKey('suggestedImprovement'), isTrue);
      expect(extract.object!.containsKey('missingOrUnclear'), isTrue);
    });

    // V1-only: live log is five-field map partial. Extractor tests above remain
    // valid under v2; runJsonTask must reject non-evidence shape when flag is on.
    test('map runJsonTask parses locally without repair or labeled fallback',
        () async {
      if (SummarizeEvidencePipeline.enabled) {
        return;
      }
      var calls = 0;
      final logs = <String>[];
      final processor = QwenTaskProcessor(
        log: logs.add,
        runner: (prompt) async {
          calls += 1;
          return taskF71a56ddMapResponseRaw;
        },
      );

      final result = await processor.runJsonTask(
        prompt: PromptTemplates.summarizeMapChunk(
          chunkText: 'Order B426 had incorrect milk; order B443 had duplicate charges.',
          chunkIndex: 0,
          totalChunks: 2,
          chunkId: 'c' * 64,
        ),
        inferenceStage: SummarizeInferenceStage.mapEvidence,
        signingKey: 'sign',
        correctiveBudget: CorrectiveInferenceBudget(),
      );

      expect(calls, 1);
      expect(
        logs.any((line) => line.contains('[JSON EXTRACT RECOVERED] method=literal_escape_layer')),
        isTrue,
      );
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
        taskF71a56ddExpectedKeyPointCount,
      );
    });

    test('map runJsonTask rejects legacy five-field payload when evidence v2 active',
        () async {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      final processor = QwenTaskProcessor(
        runner: (prompt) async => taskF71a56ddMapResponseRaw,
      );

      await expectLater(
        processor.runJsonTask(
          prompt: PromptTemplates.summarizeMapChunk(
            chunkText: 'Order B426 had incorrect milk.',
            chunkIndex: 0,
            totalChunks: 2,
            chunkId: 'c' * 64,
          ),
          inferenceStage: SummarizeInferenceStage.mapEvidence,
          signingKey: 'sign',
          correctiveBudget: CorrectiveInferenceBudget(maxCalls: 0),
        ),
        throwsA(
          isA<WorkerError>().having(
            (error) => error.code,
            'code',
            WorkerErrorCode.outputSchemaMismatch,
          ),
        ),
      );
    });

    test('reports decode failure when literal-escape layer stays truncated',
        () {
      const truncated =
          '```json\\n{\\n  \\"summary\\": \\"Incomplete\\",\\n  \\"keyPoints\\": [\\n    \\"one\\"';
      final extract = JsonOutputValidator.extractJsonObject(truncated);
      expect(extract.ok, isFalse);
      expect(
        extract.rejectionReason,
        anyOf('json_extract_no_object', 'json_extract_decode_failed'),
      );
    });

    test('does not accept two objects after literal-escape unwrapping', () {
      const raw =
          'json\\n{\\n  \\"summary\\": \\"first\\",\\n  \\"keyPoints\\": [\\"a\\"],\\n'
          '  \\"mainComplaint\\": \\"\\",\\n  \\"suggestedImprovement\\": \\"\\",\\n'
          '  \\"missingOrUnclear\\": []\\n}\\n'
          '{\\n  \\"summary\\": \\"second\\",\\n  \\"keyPoints\\": [\\"b\\"],\\n'
          '  \\"mainComplaint\\": \\"\\",\\n  \\"suggestedImprovement\\": \\"\\",\\n'
          '  \\"missingOrUnclear\\": []\\n}';
      final extract = JsonOutputValidator.extractJsonObject(raw);
      expect(extract.ok, isFalse);
      expect(
        extract.rejectionReason,
        'json_extract_ambiguous_multiple_objects',
      );
    });
  });
}
