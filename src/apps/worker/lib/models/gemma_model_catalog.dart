/// Canonical artifact metadata for Gemma 3n E2B INT4 (LiteRT-LM).
abstract final class GemmaModelCatalog {
  static const profileId = 'gemma-3n-e2b-int4';
  static const modelVersionId = 'mdv_gemma_3n_e2b_int4';
  static const fileName = 'gemma-3n-E2B-it-int4.litertlm';

  /// Upstream runtime referenced from google-ai-edge/LiteRT-LM on GitHub.
  static const githubProjectUrl = 'https://github.com/google-ai-edge/LiteRT-LM';

  /// Official model bundle (linked from LiteRT-LM README; gated on Hugging Face).
  static const huggingFaceDownloadUrl =
      'https://huggingface.co/google/gemma-3n-E2B-it-litert-lm/resolve/main/$fileName';

  /// Placeholder digest used when the on-device model is managed by flutter_gemma.
  static const installedDigestMarker = 'installed-on-device';

  static String downloadUrlFromEnvironment() {
    const override = String.fromEnvironment('GEMMA_MODEL_DOWNLOAD_URL');
    return override.isEmpty ? huggingFaceDownloadUrl : override;
  }

  static String? bundledAssetFromEnvironment() {
    const asset = String.fromEnvironment('GEMMA_MODEL_ASSET');
    return asset.isEmpty ? null : asset;
  }

  static String huggingFaceTokenFromEnvironment() {
    return const String.fromEnvironment('HUGGINGFACE_TOKEN');
  }
}
