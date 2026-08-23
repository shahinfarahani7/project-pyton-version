import 'package:flutter_gemma/flutter_gemma.dart';

abstract final class WorkerVisionModelCatalog {
  static const modelVersionId = 'mdv_internvl3_1b';
  static const displayName = 'InternVL3 1B';
  static const fileName = 'InternVL3-1B.litertlm';
  static const downloadUrl =
      'https://huggingface.co/litert-community/InternVL3-1B/resolve/main/$fileName';
  static const sizeBytes = 737985904;
  static const artifactSha256 =
      'c1f0dfd2794a5bcb315810099e0a0e3f774ee6b7244107c7d5ed0c0172d20279';

  static InferenceInstallationBuilder installBuilder() =>
      FlutterGemma.installModel(
        modelType: ModelType.general,
        fileType: ModelFileType.litertlm,
      );
}
