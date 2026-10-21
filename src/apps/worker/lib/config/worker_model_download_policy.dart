/// How the worker chooses the LLM artifact download URL before transfer.
enum WorkerModelDownloadSource {
  /// Hugging Face (or [WorkerModelCatalog] compile-time override URL).
  direct,

  /// Same gateway host as enrollment: `/models/{id}/files/{file}` proxy stream.
  backendProxy,

  /// `GET /models/{id}/artifact-delivery` on the worker API, then download via returned path.
  server,
}

/// Runtime / compile-time policy for model artifact delivery.
abstract final class WorkerModelDownloadPolicy {
  static const envKey = 'WORKER_MODEL_DOWNLOAD_SOURCE';
  static const legacyBackendFlag = 'WORKER_USE_BACKEND_ARTIFACT';

  static WorkerModelDownloadSource fromEnvironment() {
    const raw = String.fromEnvironment(envKey);
    if (raw.isNotEmpty) {
      return _parse(raw);
    }
    const legacyBackend = bool.fromEnvironment(
      legacyBackendFlag,
      defaultValue: false,
    );
    if (legacyBackend) {
      return WorkerModelDownloadSource.backendProxy;
    }
    return WorkerModelDownloadSource.direct;
  }

  static WorkerModelDownloadSource _parse(String raw) {
    return switch (raw.trim().toLowerCase()) {
      'direct' || 'huggingface' || 'hf' => WorkerModelDownloadSource.direct,
      'backend' ||
      'backend_proxy' ||
      'backend-proxy' ||
      'proxy' =>
        WorkerModelDownloadSource.backendProxy,
      'server' || 'manifest' || 'delivery' => WorkerModelDownloadSource.server,
      _ => throw ArgumentError(
        'Unsupported $envKey: $raw '
        '(use direct, backend, or server)',
      ),
    };
  }

  static bool usesWorkerGatewayArtifact(WorkerModelDownloadSource source) {
    return switch (source) {
      WorkerModelDownloadSource.backendProxy ||
      WorkerModelDownloadSource.server =>
        true,
      WorkerModelDownloadSource.direct => false,
    };
  }
}
