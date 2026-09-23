import 'package:edgemint_worker/contracts/worker_error.dart';
import 'package:edgemint_worker/inference/llm/prompt_templates.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/validation/json_output_validator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../inference/llm/fixtures/task_f71a56dd_map_response.dart';

/// Wraps [json] as a single-line literal-escape payload like task f71a56dd.
String encodeLiteralEscapeLayer(String json) {
  final encoded = json
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');
  return '```json\\n$encoded\\n```';
}

void main() {
  group('literal-escape recovery content preservation', () {
    test('f71 fixture hash unchanged and recovery flag set', () {
      final extract = JsonOutputValidator.extractJsonObject(
        taskF71a56ddMapResponseRaw,
      );
      expect(extract.literalEscapeRecovered, isTrue);
      expect(
        (extract.object!['keyPoints'] as List).length,
        taskF71a56ddExpectedKeyPointCount,
      );
    });

    test('preserves escaped quotes inside string values', () {
      const json =
          '{"summary":"Tracking showed \\"5 minutes away\\" for an hour.",'
          '"keyPoints":["Tracking showed \\"5 minutes away\\""],'
          '"mainComplaint":"Late delivery",'
          '"suggestedImprovement":"Use driver location",'
          '"missingOrUnclear":[]}';
      final extract = JsonOutputValidator.extractJsonObject(
        encodeLiteralEscapeLayer(json),
      );
      expect(extract.literalEscapeRecovered, isTrue, reason: extract.rejectionReason);
      expect(
        extract.object!['summary'],
        'Tracking showed "5 minutes away" for an hour.',
      );
      expect(
        extract.object!['keyPoints'],
        ['Tracking showed "5 minutes away"'],
      );
    });

    test('preserves Windows paths and literal backslashes in values', () {
      const json =
          r'{"summary":"Saved to C:\\Users\\test\\file.txt","keyPoints":["a"],'
          r'"mainComplaint":"","suggestedImprovement":"","missingOrUnclear":[]}';
      final extract = JsonOutputValidator.extractJsonObject(
        encodeLiteralEscapeLayer(json),
      );
      expect(extract.literalEscapeRecovered, isTrue, reason: extract.rejectionReason);
      expect(
        extract.object!['summary'],
        r'Saved to C:\Users\test\file.txt',
      );
    });

    test('preserves literal backslash-n token distinct from real newline', () {
      const json =
          r'{"summary":"Token uses \n not a break","keyPoints":["a"],'
          r'"mainComplaint":"","suggestedImprovement":"","missingOrUnclear":[]}';
      final extract = JsonOutputValidator.extractJsonObject(
        encodeLiteralEscapeLayer(json),
      );
      expect(extract.literalEscapeRecovered, isTrue, reason: extract.rejectionReason);
      expect(extract.object!['summary'], r'Token uses \n not a break');
      expect(extract.object!['summary'].contains('\n'), isFalse);
    });

    test('preserves real newline inside a value after unescape', () {
      const json =
          '{"summary":"Line one\nLine two","keyPoints":["a"],'
          '"mainComplaint":"","suggestedImprovement":"","missingOrUnclear":[]}';
      final extract = JsonOutputValidator.extractJsonObject(
        encodeLiteralEscapeLayer(json),
      );
      expect(extract.literalEscapeRecovered, isTrue, reason: extract.rejectionReason);
      expect(extract.object!['summary'], 'Line one\nLine two');
    });

    test('preserves unicode escape sequences in values', () {
      const json =
          r'{"summary":"Letter \u0041","keyPoints":["\u0042"],'
          r'"mainComplaint":"","suggestedImprovement":"","missingOrUnclear":[]}';
      final extract = JsonOutputValidator.extractJsonObject(
        encodeLiteralEscapeLayer(json),
      );
      expect(extract.literalEscapeRecovered, isTrue, reason: extract.rejectionReason);
      expect(extract.object!['summary'], 'Letter A');
      expect(extract.object!['keyPoints'], ['B']);
    });

    test('rejects truncated literal-escape payloads', () {
      const truncated =
          '```json\\n{\\n  \\"summary\\": \\"Incomplete\\",\\n  \\"keyPoints\\": [\\n    \\"one\\"';
      final extract = JsonOutputValidator.extractJsonObject(truncated);
      expect(extract.ok, isFalse);
      expect(extract.literalEscapeRecovered, isFalse);
    });

    test('rejects multiple objects after unescape', () {
      const raw =
          'json\\n{\\n  \\"summary\\": \\"first\\",\\n  \\"keyPoints\\": [\\"a\\"],\\n'
          '  \\"mainComplaint\\": \\"\\",\\n  \\"suggestedImprovement\\": \\"\\",\\n'
          '  \\"missingOrUnclear\\": []\\n}\\n'
          '{\\n  \\"summary\\": \\"second\\",\\n  \\"keyPoints\\": [\\"b\\"],\\n'
          '  \\"mainComplaint\\": \\"\\",\\n  \\"suggestedImprovement\\": \\"\\",\\n'
          '  \\"missingOrUnclear\\": []\\n}';
      final extract = JsonOutputValidator.extractJsonObject(raw);
      expect(extract.ok, isFalse);
      expect(extract.literalEscapeRecovered, isFalse);
    });

    test('rejects mixed encoding with trailing prose after unescaped object', () {
      const raw =
          'json\\n{\\n  \\"summary\\": \\"ok\\",\\n  \\"keyPoints\\": [\\"a\\"],\\n'
          '  \\"mainComplaint\\": \\"\\",\\n  \\"suggestedImprovement\\": \\"\\",\\n'
          '  \\"missingOrUnclear\\": []\\n}\\n'
          'Extra prose that is not a fence fragment';
      final extract = JsonOutputValidator.extractJsonObject(raw);
      expect(extract.ok, isFalse);
      expect(extract.literalEscapeRecovered, isFalse);
    });

    test('does not apply recovery to already-valid JSON with escapes in values', () {
      const raw =
          '{"summary":"Line one\\nLine two","keyPoints":["a"],'
          '"mainComplaint":"","suggestedImprovement":"","missingOrUnclear":[]}';
      final extract = JsonOutputValidator.extractJsonObject(raw);
      expect(extract.ok, isTrue, reason: extract.rejectionReason);
      expect(extract.literalEscapeRecovered, isFalse);
      expect(extract.object!['summary'], 'Line one\nLine two');
    });
  });

  group('map stage blocks salvage-cut before literal-escape recovery', () {
    const salvagedOnly =
        '{"summary":"Deliveries were late.",'
        '"keyPoints":["Order A184 arrived at 19:35","Refund is pending"],'
        '"mainComplaint":"Late delivery",'
        '"suggestedImprovement":"The customer should che';

    test('non-map extraction may still salvage truncated JSON', () {
      final extract = JsonOutputValidator.extractJsonObject(salvagedOnly);
      expect(extract.ok, isTrue, reason: extract.rejectionReason);
      expect(extract.literalEscapeRecovered, isFalse);
    });

    test('map stage rejects salvage-cut even when truncated=false', () async {
      var calls = 0;
      final logs = <String>[];
      final processor = QwenTaskProcessor(
        log: logs.add,
        runner: (prompt) async {
          calls += 1;
          return salvagedOnly;
        },
      );

      await expectLater(
        processor.runJsonTask(
          prompt: PromptTemplates.summarizeMapChunk(
            chunkText: 'Order A184 arrived late.',
            chunkIndex: 0,
            totalChunks: 2,
            chunkId: 'c' * 64,
          ),
          signingKey: 'sign',
          correctiveBudget: CorrectiveInferenceBudget(maxCalls: 0),
        ),
        throwsA(isA<WorkerError>()),
      );
      expect(calls, 1);
      expect(
        logs.any((line) => line.contains('[JSON EXTRACT RECOVERED]')),
        isFalse,
      );
    });
  });
}
