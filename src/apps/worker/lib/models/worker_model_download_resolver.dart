import '../api/worker_api_client.dart';
import '../config/worker_config.dart';
import '../config/worker_model_download_policy.dart';
import 'worker_model_catalog.dart';

/// Resolves the HTTP(S) URL used by [ResumableModelDownload].
abstract final class WorkerModelDownloadResolver {
  static const compileTimeOverrideKey = 'WORKER_MODEL_DOWNLOAD_URL';

  /// Synchronous URL for UI hints and offline builds (no server round-trip).
  static String resolveStatic({
    required WorkerConfig config,
    required WorkerModelDownloadSource source,
    String artifactFileName = WorkerModelCatalog.fileName,
    String artifactModelVersionId = WorkerModelCatalog.modelVersionId,
  }) {
    const override = String.fromEnvironment(compileTimeOverrideKey);
    if (override.isNotEmpty) {
      return override;
    }
    return switch (source) {
      WorkerModelDownloadSource.direct =>
        WorkerModelCatalog.huggingFaceDownloadUrlForFile(artifactFileName),
      WorkerModelDownloadSource.backendProxy =>
        WorkerModelCatalog.backendArtifactFileUrl(
          config.baseUrl,
          artifactModelVersionId: artifactModelVersionId,
          artifactFileName: artifactFileName,
        ),
      WorkerModelDownloadSource.server => config
          .resolve(
            WorkerModelCatalog.artifactDeliveryPath(artifactModelVersionId),
          )
          .toString(),
    };
  }

  /// Production download URL; may call the worker API when [source] is [WorkerModelDownloadSource.server].
  static Future<String> resolveForDownload({
    required WorkerConfig config,
    required WorkerModelDownloadSource source,
    required WorkerApiClient api,
    required String accessToken,
    String artifactFileName = WorkerModelCatalog.fileName,
    String artifactModelVersionId = WorkerModelCatalog.modelVersionId,
    String? expectedSha256 = WorkerModelCatalog.knownGeneralArtifactSha256,
    int? expectedSizeBytes = WorkerModelCatalog.knownGeneralArtifactSizeBytes,
  }) async {
    const override = String.fromEnvironment(compileTimeOverrideKey);
    if (override.isNotEmpty) {
      return override;
    }

    switch (source) {
      case WorkerModelDownloadSource.direct:
        return WorkerModelCatalog.huggingFaceDownloadUrlForFile(artifactFileName);
      case WorkerModelDownloadSource.backendProxy:
        return WorkerModelCatalog.backendArtifactFileUrl(
          config.baseUrl,
          artifactModelVersionId: artifactModelVersionId,
          artifactFileName: artifactFileName,
        );
      case WorkerModelDownloadSource.server:
        if (accessToken.isEmpty) {
          throw StateError('Worker session required for server model delivery');
        }
        final delivery = await api.getModelArtifactDelivery(
          modelVersionId: artifactModelVersionId,
          accessToken: accessToken,
        );
        if (expectedSha256 != null &&
            delivery.artifactSha256 != null &&
            delivery.artifactSha256 != expectedSha256) {
          throw StateError(
            'Server artifact digest does not match pinned catalog identity',
          );
        }
        if (expectedSizeBytes != null &&
            delivery.sizeBytes != null &&
            delivery.sizeBytes != expectedSizeBytes) {
          throw StateError(
            'Server artifact size does not match pinned catalog identity',
          );
        }
        if (delivery.fileName != artifactFileName) {
          throw StateError('Server artifact file name mismatch');
        }
        if (delivery.downloadUrl != null && delivery.downloadUrl!.isNotEmpty) {
          return delivery.downloadUrl!;
        }
        final path = delivery.downloadPath;
        if (path == null || path.isEmpty) {
          throw StateError('Server model delivery did not include a download path');
        }
        return config.resolve(path).toString();
    }
  }
}
