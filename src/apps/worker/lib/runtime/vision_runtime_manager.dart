import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../contracts/worker_error.dart';
import '../inference/vision/lightweight_vision.dart';
import 'vision_litert_adapter.dart';
import 'vision_runtime_catalog.dart';

/// Routes vision workloads to distinct runtime classes (Section 59).
class VisionRuntimeManager {
  VisionRuntimeManager({
    VisionLiteRtAdapter? vlmAdapter,
    LightweightVision? classifier,
    MethodChannel? segmentationChannel,
  })  : _vlmAdapter = vlmAdapter ?? VisionLiteRtAdapter(),
        _classifier = classifier ?? const LightweightVision(),
        _segmentationChannel =
            segmentationChannel ?? const MethodChannel('io.edgemint/image_segmenter');

  final VisionLiteRtAdapter _vlmAdapter;
  final LightweightVision _classifier;
  final MethodChannel _segmentationChannel;

  VisionRuntimeKind runtimeKindFor(String capability) =>
      VisionRuntimeCatalog.kindFor(capability);

  String runtimeClassFor(String capability) =>
      VisionRuntimeCatalog.runtimeClassForCapability(capability);

  Future<String> inferVlm({
    required Uint8List imageBytes,
    required String prompt,
  }) {
    return _vlmAdapter.runRaw(imageBytes: imageBytes, prompt: prompt);
  }

  Future<Uint8List> segmentBackground({required Uint8List imageBytes}) async {
    try {
      final png = await _segmentationChannel.invokeMethod<Uint8List>(
        'removeBackground',
        {'imageBytes': imageBytes},
      );
      if (png == null || png.isEmpty) {
        throw StateError('Empty segmentation output');
      }
      return png;
    } on PlatformException catch (error) {
      throw WorkerError(
        code: WorkerErrorCode.modelNotAvailable,
        message: 'Image segmentation failed: ${error.message}',
        retryable: true,
        stage: WorkerTaskStage.llm,
      );
    }
  }

  Map<String, dynamic> classifyBlur(Uint8List imageBytes) {
    final variance = _classifier.blurVariance(imageBytes);
    return {
      'laplacianVariance': variance,
      'blurry': variance < 100,
      'threshold': 100,
    };
  }

  Map<String, dynamic> classifyDocumentQuality(Uint8List imageBytes) =>
      _classifier.documentQuality(imageBytes);

  Map<String, dynamic> classifyDuplicate(
    Uint8List imageBytes,
    Uint8List compareImageBytes,
  ) =>
      _classifier.duplicate(imageBytes, compareImageBytes);

  Future<void> dispose() => _vlmAdapter.dispose();
}
