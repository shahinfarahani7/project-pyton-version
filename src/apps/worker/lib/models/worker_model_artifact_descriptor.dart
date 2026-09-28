import 'package:flutter_gemma/flutter_gemma.dart';

/// Source packaging of weights on disk (may differ from runnable runtime).
enum WorkerModelSourceFormat {
  litertLm,
  safetensorsQat,
  unknown,
}

/// Format the active inference engine consumes.
enum WorkerModelRuntimeFormat {
  litertLm,
  none,
}

enum WorkerModelRuntimeEngine {
  litertLm,
  none,
}

/// Intended LiteRT backend target for a runtime artifact (not the process CPU/GPU policy alone).
enum WorkerModelTargetBackend {
  general,
  gpu,
}

enum WorkerModelQuantizationProfile {
  /// Official LiteRT-LM Gemma 4 bundle (mixed low-bit / QAT-derived runtime).
  litertLmGemma4QatRuntime,
  /// Hugging Face `quant_method=gemma` packed mobile checkpoint.
  gemmaQatMobilePackedSafetensors,
  unknown,
}

/// Immutable catalog entry for one model artifact identity.
class WorkerModelArtifactDescriptor {
  const WorkerModelArtifactDescriptor({
    required this.modelId,
    required this.modelFamily,
    required this.variant,
    required this.sourceFormat,
    required this.runtimeFormat,
    required this.runtimeEngine,
    required this.artifactFileName,
    required this.modelType,
    required this.quantizationProfile,
    required this.maxSupportedContext,
    required this.configuredRuntimeContext,
    required this.supportsText,
    this.targetBackend = WorkerModelTargetBackend.general,
    this.artifactSha256 = '',
    this.supportsVision = false,
    this.supportsAudio = false,
    this.supportsThinking = false,
    this.supportsFunctionCalling = false,
  });

  final String modelId;
  final String modelFamily;
  final String variant;
  final WorkerModelSourceFormat sourceFormat;
  final WorkerModelRuntimeFormat runtimeFormat;
  final WorkerModelRuntimeEngine runtimeEngine;
  final String artifactFileName;
  final WorkerModelTargetBackend targetBackend;
  final String artifactSha256;
  final WorkerModelQuantizationProfile quantizationProfile;
  final ModelType modelType;
  final int maxSupportedContext;
  final int configuredRuntimeContext;
  final bool supportsText;
  final bool supportsVision;
  final bool supportsAudio;
  final bool supportsThinking;
  final bool supportsFunctionCalling;

  bool get isRuntimeReady => runtimeFormat != WorkerModelRuntimeFormat.none;
}
