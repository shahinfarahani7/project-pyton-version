import 'dart:typed_data';

import '../../contracts/worker_error.dart';
import '../../contracts/worker_task_result.dart';
import '../llm/qwen_task_processor.dart';
import 'ocr_engine.dart';
import 'ocr_text_normalizer.dart';

/// OCR via the resident Gemma multimodal path (no Paddle ONNX).
class GemmaMultimodalOcrEngine implements OcrEngine, OcrSigningKeyBinding {
  GemmaMultimodalOcrEngine(this._processor);

  final QwenTaskProcessor _processor;
  String? _signingKey;

  static const transcribePrompt =
      'Transcribe every line of visible text in this image. '
      'Preserve reading order. Output plain text only, one line per line of text. '
      'Do not add commentary or markdown.';

  @override
  void bindSigningKey(String signingKey) {
    _signingKey = signingKey;
  }

  @override
  void unbindSigningKey() {
    _signingKey = null;
  }

  String _requireSigningKey() {
    final key = _signingKey;
    if (key == null || key.isEmpty) {
      throw StateError('Gemma OCR requires an active assignment signing key');
    }
    return key;
  }

  @override
  Future<bool> isReady() async {
    if (_processor.requiresNativeRuntime && _signingKey != null) {
      try {
        await _processor.ensureRuntimeResident(signingKey: _signingKey!);
        return true;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  @override
  Future<void> ensureLoaded() async {
    if (!_processor.requiresNativeRuntime) {
      return;
    }
    await _processor.ensureRuntimeResident(signingKey: _requireSigningKey());
  }

  @override
  Future<OcrRecognitionResult> recognize({
    required List<int> imageBytes,
    double minConfidence = 0.55,
    int maxSidePx = 1600,
  }) async {
    final raw = await _processor.runDirectUserText(
      transcribePrompt,
      signingKey: _requireSigningKey(),
      imageBytes: Uint8List.fromList(imageBytes),
      maxOutputTokens: 1024,
    );
    final lines = _linesFromTranscript(raw.trim(), minConfidence: minConfidence);
    if (lines.isEmpty) {
      throw const WorkerError(
        code: WorkerErrorCode.ocrNoText,
        message: 'Gemma multimodal OCR produced no text lines',
        retryable: true,
        stage: WorkerTaskStage.ocr,
      );
    }
    final normalized = OcrTextNormalizer.normalizeLines(lines);
    return OcrRecognitionResult(
      lines: normalized,
      rawText: OcrTextNormalizer.joinRawText(normalized),
      averageConfidence: OcrTextNormalizer.averageConfidence(normalized),
    );
  }

  static List<OcrLineResult> _linesFromTranscript(
    String raw, {
    required double minConfidence,
  }) {
    if (raw.isEmpty) {
      return const [];
    }
    final confidence = minConfidence.clamp(0.0, 1.0);
    return raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map(
          (text) => OcrLineResult(
            text: text,
            confidence: confidence,
            box: const [0, 0, 0, 0],
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> dispose() async {}
}
