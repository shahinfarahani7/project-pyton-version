import 'guarded_ocr_engine.dart';
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

/// Assignment-scoped signing material for OCR engines that delegate to the LLM.
abstract interface class OcrSigningKeyBinding {
  void bindSigningKey(String signingKey);
  void unbindSigningKey();
}

/// Swappable delegate for dev vs native OCR without rebuilding the task engine.
class OcrEngineRef implements OcrEngine {
  OcrEngineRef(this._delegate);

  OcrEngine _delegate;

  set delegate(OcrEngine engine) => _delegate = engine;

  void bindSigningKeyIfSupported(String signingKey) {
    _resolveSigningKeyTarget(_delegate)?.bindSigningKey(signingKey);
  }

  void unbindSigningKeyIfSupported() {
    _resolveSigningKeyTarget(_delegate)?.unbindSigningKey();
  }

  static OcrSigningKeyBinding? _resolveSigningKeyTarget(OcrEngine engine) {
    final resolved =
        engine is GuardedOcrEngine ? engine.innerDelegate : engine;
    if (resolved is OcrSigningKeyBinding) {
      return resolved as OcrSigningKeyBinding;
    }
    return null;
  }

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
