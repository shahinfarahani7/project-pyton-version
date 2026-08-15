import 'package:edgemint_worker/contracts/worker_task_result.dart';
import 'package:edgemint_worker/inference/ocr/ocr_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserves Persian line order by vertical box coordinate', () {
    final lines = OcrTextNormalizer.normalizeLines(const [
      OcrLineResult(text: '  line two  ', confidence: 0.9, box: [0, 40, 10, 50]),
      OcrLineResult(text: 'line one', confidence: 0.95, box: [0, 10, 10, 20]),
    ]);
    expect(lines.first.text, 'line one');
    expect(lines.last.text, 'line two');
  });
}
