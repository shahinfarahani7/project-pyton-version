/// Runtime configuration for the worker HTTP client.
class WorkerConfig {
  const WorkerConfig({
    required this.baseUrl,
    this.requestTimeout = const Duration(seconds: 30),
  });

  final Uri baseUrl;
  final Duration requestTimeout;

  static WorkerConfig fromEnvironment() {
    const raw = String.fromEnvironment(
      'EDGEMINT_WORKER_BASE_URL',
      defaultValue: 'http://172.20.34.71:8081',
    );
    return WorkerConfig(baseUrl: Uri.parse(raw));
  }

  Uri resolve(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    final basePath = baseUrl.path.endsWith('/') ? baseUrl.path.substring(0, baseUrl.path.length - 1) : baseUrl.path;
    return baseUrl.replace(path: '$basePath$normalized');
  }
}
