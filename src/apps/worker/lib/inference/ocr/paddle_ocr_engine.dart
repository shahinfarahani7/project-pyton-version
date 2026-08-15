import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../../contracts/worker_task_result.dart';
import 'ocr_engine.dart';
import 'ocr_models.dart';

/// Android ONNX Paddle OCR via MethodChannel.
class PaddleOcrEngine implements OcrEngine {
  PaddleOcrEngine({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('io.edgemint/ocr_runtime');

  final MethodChannel _channel;
  bool _loaded = false;

  @override
  Future<bool> isReady() async {
    try {
      final ready = await _channel.invokeMethod<bool>('isReady');
      return ready == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> ensureLoaded() async {
    if (_loaded) {
      return;
    }
    final ok = await _channel.invokeMethod<bool>('ensureLoaded', {
      'detectorFile': PaddleOcrModelCatalog.detectorFile,
      'recognizerFile': PaddleOcrModelCatalog.recognizerFile,
      'dictFile': PaddleOcrModelCatalog.dictFile,
      'modelDir': PaddleOcrModelCatalog.deviceRelativeDir,
    });
    if (ok != true) {
      throw StateError('PaddleOCR models not available on device');
    }
    _loaded = true;
  }

  @override
  Future<OcrRecognitionResult> recognize({
    required List<int> imageBytes,
    double minConfidence = 0.55,
    int maxSidePx = 1600,
  }) async {
    await ensureLoaded();
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('recognize', {
      'imageBytes': Uint8List.fromList(imageBytes),
      'maxSidePx': maxSidePx,
      'minConfidence': minConfidence,
    });
    if (raw == null) {
      throw StateError('OCR returned null');
    }
    final linesRaw = raw['lines'] as List<Object?>? ?? [];
    final lines = linesRaw.map((entry) {
      final map = Map<String, dynamic>.from(entry! as Map);
      final box = (map['box'] as List<dynamic>? ?? [])
          .map((e) => (e as num).toInt())
          .toList();
      return OcrLineResult(
        text: map['text'] as String? ?? '',
        confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
        box: box,
        belowThreshold: map['belowThreshold'] == true,
      );
    }).toList();
    return OcrRecognitionResult(
      lines: lines,
      rawText: raw['rawText'] as String? ?? '',
      averageConfidence: (raw['averageConfidence'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  Future<void> dispose() async {
    _loaded = false;
    try {
      await _channel.invokeMethod<void>('dispose');
    } catch (_) {}
  }
}
