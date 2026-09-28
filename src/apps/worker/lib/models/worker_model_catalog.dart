import 'package:flutter_gemma/flutter_gemma.dart';

import 'worker_model_artifact_descriptor.dart';
import '../runtime/encrypted_store.dart';
import '../runtime/model_artifact_verifier.dart';

/// Canonical on-device LLM: Google Gemma 4 E4B IT via LiteRT-LM.
abstract final class WorkerModelCatalog {
  static const profileId = 'gemma-4-e4b-it';

  static const modelVersionId = 'mdv_gemma_4_e4b_it';

  static const displayName = 'Gemma 4 E4B IT';

  static const fileName = 'gemma-4-E4B-it.litertlm';

  static const gpuFileName = 'gemma-4-E4B-it-gpu.litertlm';

  static const gpuModelVersionId = 'mdv_gemma_4_e4b_it_gpu';

  /// Verified from Hugging Face LFS metadata (2026-09-28).
  static const knownGeneralArtifactSha256 =
      '0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0';

  static const knownGeneralArtifactSizeBytes = 3659530240;

  /// Verified from Hugging Face LFS metadata (2026-09-28).
  static const knownGpuArtifactSha256 =
      '4912bb5a9c30993c51a7711f763212077458529312175df0573a78323a2bb7ff';

  static const knownGpuArtifactSizeBytes = 2969059328;

  static const gpuApproximateDownloadSize = '~2.97 GB';

  static const gpuHuggingFaceDownloadUrl =
      'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/$gpuFileName';

  /// Local QAT mobile source (evaluation only; not runtime-ready).
  static const qatSourceFileName = 'model.safetensors';

  static const qatSourceRelativePath = 'assets/models/$qatSourceFileName';

  static const verifiedArtifactContextLimit = 4096;

  static const runtimeMaxTokens = 4096;

  static const outputReserveTokens = 256;

  static const benchmarkContextTokens = 2048;

  static const benchmarkMaxOutputTokens = 256;

  static const approximateDownloadSize = '~3.7 GB';

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

  /// Active production runtime artifact (Candidate A).
  static const WorkerModelArtifactDescriptor generalRuntimeDescriptor =
      WorkerModelArtifactDescriptor(
    modelId: modelVersionId,
    modelFamily: 'gemma4',
    variant: 'e4b-it-litertlm',
    sourceFormat: WorkerModelSourceFormat.litertLm,
    runtimeFormat: WorkerModelRuntimeFormat.litertLm,
    runtimeEngine: WorkerModelRuntimeEngine.litertLm,
    artifactFileName: fileName,
    targetBackend: WorkerModelTargetBackend.general,
    artifactSha256: knownGeneralArtifactSha256,
    quantizationProfile:
        WorkerModelQuantizationProfile.litertLmGemma4QatRuntime,
    modelType: ModelType.gemma4,
    maxSupportedContext: 4096,
    configuredRuntimeContext: verifiedArtifactContextLimit,
    supportsText: true,
    supportsVision: true,
    supportsAudio: true,
    supportsThinking: true,
    supportsFunctionCalling: true,
  );

  /// Alias — production default remains Candidate A.
  static const WorkerModelArtifactDescriptor activeRuntimeDescriptor =
      generalRuntimeDescriptor;

  /// GPU-targeted LiteRT-LM artifact (Candidate G — benchmark/selectable).
  static const WorkerModelArtifactDescriptor gpuRuntimeDescriptor =
      WorkerModelArtifactDescriptor(
    modelId: gpuModelVersionId,
    modelFamily: 'gemma4',
    variant: 'e4b-it-gpu-litertlm',
    sourceFormat: WorkerModelSourceFormat.litertLm,
    runtimeFormat: WorkerModelRuntimeFormat.litertLm,
    runtimeEngine: WorkerModelRuntimeEngine.litertLm,
    artifactFileName: gpuFileName,
    targetBackend: WorkerModelTargetBackend.gpu,
    artifactSha256: knownGpuArtifactSha256,
    quantizationProfile:
        WorkerModelQuantizationProfile.litertLmGemma4QatRuntime,
    modelType: ModelType.gemma4,
    maxSupportedContext: 4096,
    configuredRuntimeContext: verifiedArtifactContextLimit,
    supportsText: true,
    supportsVision: true,
    supportsAudio: true,
    supportsThinking: true,
    supportsFunctionCalling: true,
  );

  /// Google QAT mobile Transformers checkpoint (Candidate B source; not runnable).
  static const WorkerModelArtifactDescriptor qatMobileSourceDescriptor =
      WorkerModelArtifactDescriptor(
    modelId: 'google-gemma-4-e4b-it-qat-mobile-transformers',
    modelFamily: 'gemma4',
    variant: 'qat-mobile-safetensors',
    sourceFormat: WorkerModelSourceFormat.safetensorsQat,
    runtimeFormat: WorkerModelRuntimeFormat.none,
    runtimeEngine: WorkerModelRuntimeEngine.none,
    artifactFileName: qatSourceFileName,
    quantizationProfile:
        WorkerModelQuantizationProfile.gemmaQatMobilePackedSafetensors,
    modelType: ModelType.gemma4,
    maxSupportedContext: 4096,
    configuredRuntimeContext: 0,
    supportsText: true,
    supportsVision: true,
    supportsAudio: true,
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

  static String resolveDownloadUrl(
    Uri workerBaseUrl, {
    String artifactFileName = fileName,
    String artifactModelVersionId = modelVersionId,
  }) {
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
            path:
                '$basePath/models/$artifactModelVersionId/files/$artifactFileName',
          )
          .toString();
    }

    return 'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/$artifactFileName';
  }

  /// Optional `.litertlm` bundled asset path (`WORKER_MODEL_ASSET=none` disables).
  /// Safetensors bundles are rejected by [WorkerModelFormatGate].
  static String? bundledAssetFromEnvironment() {
    const asset = String.fromEnvironment('WORKER_MODEL_ASSET');
    if (asset == 'none') {
      return null;
    }
    if (asset.isNotEmpty) {
      return asset;
    }
    return null;
  }

  static InferenceInstallationBuilder installBuilder() {
    return FlutterGemma.installModel(
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm,
    );
  }

  static WorkerModelArtifactDescriptor descriptorForArtifactFileName(
    String artifactName,
  ) {
    if (artifactName == gpuFileName) {
      return gpuRuntimeDescriptor;
    }
    return generalRuntimeDescriptor;
  }

  static PreferredBackend preferredInferenceBackend({required bool isX86Android}) {
    return isX86Android ? PreferredBackend.cpu : PreferredBackend.gpu;
  }
}
