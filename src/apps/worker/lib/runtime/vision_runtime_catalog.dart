import '../tasks/task_type_mapper.dart';

enum VisionRuntimeKind {
  vlm,
  segmentation,
  classifier,
}

/// Maps worker vision capabilities to Section 59 runtime classes.
abstract final class VisionRuntimeCatalog {
  static const lightweightCapabilities = {
    'quality.blurry_image',
    'quality.document_image',
    'catalog.duplicate_image',
  };

  static bool isVisionCapability(String capability) =>
      capability == TaskTypeMapper.visionAnalyze ||
      capability == TaskTypeMapper.removeBackground ||
      lightweightCapabilities.contains(capability);

  static VisionRuntimeKind kindFor(String capability) {
    if (capability == TaskTypeMapper.visionAnalyze) {
      return VisionRuntimeKind.vlm;
    }
    if (capability == TaskTypeMapper.removeBackground) {
      return VisionRuntimeKind.segmentation;
    }
    if (lightweightCapabilities.contains(capability)) {
      return VisionRuntimeKind.classifier;
    }
    throw ArgumentError('Not a vision capability: $capability');
  }

  static String runtimeClassId(VisionRuntimeKind kind) => switch (kind) {
        VisionRuntimeKind.vlm => 'vlm_runtime',
        VisionRuntimeKind.segmentation => 'segmentation_runtime',
        VisionRuntimeKind.classifier => 'image_classifier',
      };

  static String runtimeClassForCapability(String capability) =>
      runtimeClassId(kindFor(capability));
}
