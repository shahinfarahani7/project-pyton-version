import 'vision_runtime_catalog.dart';

abstract final class RuntimeClassCatalog {
  static const _llmCapabilities = {
    'text.summarize.v1',
    'text.classify.v1',
    'document.extract.v1',
    'document.classify.v1',
    'document.summarize.v1',
  };

  static const _vlmCapabilities = {
    'vision.analyze.v1',
  };

  static const _segmentationCapabilities = {
    'image.remove_background.v1',
  };

  static const _classifierCapabilities = {
    'quality.document_image',
    'quality.blurry_image',
    'catalog.duplicate_image',
  };

  static const _ocrCapabilities = {
    'ocr.extract_text.v1',
  };

  static List<String> fromTaskCapabilities(Iterable<String> capabilities) {
    final classes = <String>{};

    for (final capability in capabilities) {
      if (_ocrCapabilities.contains(capability)) {
        classes.add('paddle_ocr');
      }
      if (_llmCapabilities.contains(capability)) {
        classes.add('mediapipe_llm');
      }
      if (_vlmCapabilities.contains(capability)) {
        classes.add('vlm_runtime');
      }
      if (_segmentationCapabilities.contains(capability)) {
        classes.add('segmentation_runtime');
      }
      if (_classifierCapabilities.contains(capability)) {
        classes.add('image_classifier');
      }
    }

    if (classes.isEmpty) {
      classes.add('system');
    }

    return classes.toList()..sort();
  }
}
