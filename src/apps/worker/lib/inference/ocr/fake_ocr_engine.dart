import '../../contracts/worker_task_result.dart';
import 'ocr_engine.dart';
import 'ocr_text_normalizer.dart';

/// Test/dev OCR engine — no native models required.
class FakeOcrEngine implements OcrEngine {
  FakeOcrEngine({this.cannedLines = const []});

  final List<OcrLineResult> cannedLines;
  int recognizeCalls = 0;

  @override
  Future<bool> isReady() async => true;

  @override
  Future<void> ensureLoaded() async {}

  @override
  Future<OcrRecognitionResult> recognize({
    required List<int> imageBytes,
    double minConfidence = 0.55,
    int maxSidePx = 1600,
  }) async {
    recognizeCalls++;
    final lines = cannedLines.isNotEmpty
        ? cannedLines
        : [
            const OcrLineResult(
              text: 'Sample Store',
              confidence: 0.93,
              box: [12, 40, 410, 92],
            ),
            const OcrLineResult(
              text: 'Total amount: 2450000 IRR',
              confidence: 0.91,
              box: [12, 100, 410, 140],
            ),
          ];
    final normalized = OcrTextNormalizer.normalizeLines(lines);
    return OcrRecognitionResult(
      lines: normalized,
      rawText: OcrTextNormalizer.joinRawText(normalized),
      averageConfidence: OcrTextNormalizer.averageConfidence(normalized),
    );
  }

  @override
  Future<void> dispose() async {}
}
