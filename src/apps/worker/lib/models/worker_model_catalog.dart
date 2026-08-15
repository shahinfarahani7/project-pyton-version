// Canonical artifact metadata for the on-device worker LLM (LiteRT-LM).

import 'package:flutter_gemma/flutter_gemma.dart';

abstract final class WorkerModelCatalog {
  static const profileId = 'qwen3-0.6b';

  static const modelVersionId = 'mdv_qwen3_0_6b';

  static const displayName = 'Qwen3 0.6B';

  static const fileName = 'Qwen3-0.6B.litertlm';

  static const approximateDownloadSize = '~586 MB';

  static const huggingFaceDownloadUrl =
      'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/$fileName';

  /// Placeholder digest used when the on-device model is managed by flutter_gemma.
  static const installedDigestMarker = 'installed-on-device';

  static const _useBackendArtifact = bool.fromEnvironment(
    'WORKER_USE_BACKEND_ARTIFACT',
    defaultValue: true,
  );

  static bool usesBackendArtifactProxy() {
    const override = String.fromEnvironment('WORKER_MODEL_DOWNLOAD_URL');
    if (override.isNotEmpty) {
      return false;
    }
    return _useBackendArtifact;
  }

  static String resolveDownloadUrl(Uri workerBaseUrl) {
    const override = String.fromEnvironment('WORKER_MODEL_DOWNLOAD_URL');
    if (override.isNotEmpty) {
      return override;
    }
    if (usesBackendArtifactProxy()) {
      final basePath = workerBaseUrl.path.endsWith('/')
          ? workerBaseUrl.path.substring(0, workerBaseUrl.path.length - 1)
          : workerBaseUrl.path;
      // Path must end with the real filename — flutter_gemma names local files
      // from the URL basename (not Content-Disposition).
      return workerBaseUrl
          .replace(path: '$basePath/models/$modelVersionId/files/$fileName')
          .toString();
    }
    return huggingFaceDownloadUrl;
  }

  static String? bundledAssetFromEnvironment() {
    const asset = String.fromEnvironment('WORKER_MODEL_ASSET');
    return asset.isEmpty ? null : asset;
  }

  /// Qwen3-0.6B ships as `.litertlm` — must NOT use default `.task` (MediaPipe).
  static InferenceInstallationBuilder installBuilder() {
    return FlutterGemma.installModel(
      modelType: ModelType.qwen3,
      fileType: ModelFileType.litertlm,
    );
  }
}
