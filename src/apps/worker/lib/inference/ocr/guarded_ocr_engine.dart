import 'ocr_engine.dart';
import '../../runtime/runtime_exclusive_group_enforcer.dart';

/// OCR engine wrapper that acquires paddle_ocr exclusive-group admission.
class GuardedOcrEngine implements OcrEngine {
  GuardedOcrEngine({
    required OcrEngine delegate,
    required RuntimeExclusiveGroupEnforcer exclusiveGroups,
  })  : _delegate = delegate,
        _exclusiveGroups = exclusiveGroups;

  final OcrEngine _delegate;
  final RuntimeExclusiveGroupEnforcer _exclusiveGroups;

  @override
  Future<bool> isReady() => _delegate.isReady();

  @override
  Future<void> ensureLoaded() =>
      _exclusiveGroups.withOcrInference(_delegate.ensureLoaded);

  @override
  Future<OcrRecognitionResult> recognize({
    required List<int> imageBytes,
    double minConfidence = 0.55,
    int maxSidePx = 1600,
  }) {
    return _exclusiveGroups.withOcrInference(
      () => _delegate.recognize(
        imageBytes: imageBytes,
        minConfidence: minConfidence,
        maxSidePx: maxSidePx,
      ),
    );
  }

  @override
  Future<void> dispose() => _delegate.dispose();
}
