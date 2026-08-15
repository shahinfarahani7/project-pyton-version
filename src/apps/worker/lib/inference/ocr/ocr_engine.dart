import '../../contracts/worker_task_result.dart';

class OcrRecognitionResult {
  const OcrRecognitionResult({
    required this.lines,
    required this.rawText,
    required this.averageConfidence,
  });

  final List<OcrLineResult> lines;
  final String rawText;
  final double averageConfidence;
}

abstract class OcrEngine {
  Future<bool> isReady();

  Future<void> ensureLoaded();

  Future<OcrRecognitionResult> recognize({
    required List<int> imageBytes,
    double minConfidence = 0.55,
    int maxSidePx = 1600,
  });

  Future<void> dispose();
}

/// Swappable delegate for dev vs native OCR without rebuilding the task engine.
class OcrEngineRef implements OcrEngine {
  OcrEngineRef(this._delegate);

  OcrEngine _delegate;

  set delegate(OcrEngine engine) => _delegate = engine;

  @override
  Future<bool> isReady() => _delegate.isReady();

  @override
  Future<void> ensureLoaded() => _delegate.ensureLoaded();

  @override
  Future<OcrRecognitionResult> recognize({
    required List<int> imageBytes,
    double minConfidence = 0.55,
    int maxSidePx = 1600,
  }) =>
      _delegate.recognize(
        imageBytes: imageBytes,
        minConfidence: minConfidence,
        maxSidePx: maxSidePx,
      );

  @override
  Future<void> dispose() => _delegate.dispose();
}
