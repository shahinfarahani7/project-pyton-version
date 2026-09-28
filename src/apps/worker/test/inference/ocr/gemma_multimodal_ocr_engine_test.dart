import 'dart:typed_data';

import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/ocr/gemma_multimodal_ocr_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GemmaMultimodalOcrEngine transcribes via runDirectUserText', () async {
    final processor = QwenTaskProcessor(
      runner: (_) async => 'Line one\nLine two',
    );
    final engine = GemmaMultimodalOcrEngine(processor)
      ..bindSigningKey('test-sign');

    final result = await engine.recognize(
      imageBytes: Uint8List.fromList([1, 2, 3]),
    );

    expect(result.lines.length, 2);
    expect(result.rawText, contains('Line one'));
  });
}
