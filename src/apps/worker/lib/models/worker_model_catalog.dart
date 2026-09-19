import 'package:flutter_gemma/flutter_gemma.dart';

import '../runtime/encrypted_store.dart';
import '../runtime/model_artifact_verifier.dart';

abstract final class WorkerModelCatalog {
  static const profileId = 'gemma-4-e4b-it';

  static const modelVersionId = 'mdv_gemma_4_e4b_it';

  static const displayName = 'Gemma 4 E4B IT';

  static const fileName = 'gemma-4-E4B-it.litertlm';

  /// Bundled dev artifact under [pubspec.yaml] `flutter.assets`.
  static const bundledAssetPath = 'assets/models/gemma-4-E4B-it.litertlm';

  /// LiteRT-LM runtime context for Gemma 4 E4B (see flutter_gemma example).
  static const verifiedArtifactContextLimit = 4096;

  static const runtimeMaxTokens = 4096;

  static const outputReserveTokens = 512;

  static const approximateDownloadSize = '~4.3 GB';

  static const huggingFaceDownloadUrl =
      'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/$fileName';

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
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm,
    );
  }
}
