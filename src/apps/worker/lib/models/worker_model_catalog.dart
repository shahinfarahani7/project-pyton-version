import 'package:flutter_gemma/flutter_gemma.dart';

import '../runtime/encrypted_store.dart';
import '../runtime/model_artifact_verifier.dart';

abstract final class WorkerModelCatalog {
  static const profileId = 'qwen2.5-1.5b';

  static const modelVersionId = 'mdv_qwen2_5_1_5b';

  static const displayName = 'Qwen2.5 1.5B';

  static const fileName =
      'Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.task';

  /// Bundled dev artifact under [pubspec.yaml] `flutter.assets`.
  static const bundledAssetPath =
      'assets/models/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.task';

  /// Verified artifact context window from LiteRT task filename (ekv4096).
  static const verifiedArtifactContextLimit = 4096;

  static const runtimeMaxTokens = 4096;

  static const outputReserveTokens = 512;

  static const approximateDownloadSize = '~1.5 GB';

  static const huggingFaceDownloadUrl =
      'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/$fileName';

  static const installedDigestMarker = 'installed-on-device';

  static const pinnedDigestSha256 = String.fromEnvironment(
    'WORKER_MODEL_DIGEST_SHA256',
    defaultValue: '',
  );

  static const pinnedSignatureSha256 = String.fromEnvironment(
    'WORKER_MODEL_SIGNATURE_SHA256',
    defaultValue: '',
  );

  static String installedAttestationSignature(String signingKey) =>
      sha256HexString('$installedDigestMarker:$signingKey');

  static ModelVerificationPin? verificationPin() {
    if (pinnedDigestSha256.isEmpty || pinnedSignatureSha256.isEmpty) {
      return null;
    }
    return ModelVerificationPin(
      digestSha256: pinnedDigestSha256,
      signatureSha256: pinnedSignatureSha256,
    );
  }

  static const _useBackendArtifact = bool.fromEnvironment(
    'WORKER_USE_BACKEND_ARTIFACT',
    defaultValue: false,
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
          ? workerBaseUrl.path.substring(
              0,
              workerBaseUrl.path.length - 1,
            )
          : workerBaseUrl.path;

      return workerBaseUrl
          .replace(
            path: '$basePath/models/$modelVersionId/files/$fileName',
          )
          .toString();
    }

    return huggingFaceDownloadUrl;
  }

  /// Returns the bundled asset path by default so dev builds pick up
  /// [bundledAssetPath] without an extra `--dart-define`. Override with
  /// `WORKER_MODEL_ASSET=` to disable bundling.
  static String? bundledAssetFromEnvironment() {
    const asset = String.fromEnvironment('WORKER_MODEL_ASSET');
    if (asset == 'none') {
      return null;
    }
    if (asset.isNotEmpty) {
      return asset;
    }
    return bundledAssetPath;
  }

  static InferenceInstallationBuilder installBuilder() {
    return FlutterGemma.installModel(
      modelType: ModelType.qwen,
      fileType: ModelFileType.task,
    );
  }

  /// x86 Android emulators lack OpenCL; GPU backend crashes in native LiteRT.
  static PreferredBackend preferredInferenceBackend({required bool isX86Android}) {
    return isX86Android ? PreferredBackend.cpu : PreferredBackend.gpu;
  }
}
