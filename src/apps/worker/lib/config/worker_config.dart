/// Runtime configuration for the worker HTTP client.
class WorkerConfig {
  WorkerConfig({
    required this.baseUrl,
    this.requestTimeout = const Duration(seconds: 10),
  });

  Uri baseUrl;
  final Duration requestTimeout;

  static WorkerConfig fromEnvironment() {
    const raw = String.fromEnvironment(
      'EDGEMINT_WORKER_BASE_URL',
      defaultValue: 'http://172.20.34.71:8081',
    );
    return WorkerConfig(baseUrl: Uri.parse(raw));
  }

  /// URLs tried in order when the compile-time default is unreachable.
  static List<Uri> connectionCandidates() {
    const primary = String.fromEnvironment(
      'EDGEMINT_WORKER_BASE_URL',
      defaultValue: 'http://172.20.34.71:8081',
    );
    final seen = <String>{};
    final candidates = <Uri>[];
    void add(String raw) {
      if (seen.add(raw)) {
        candidates.add(Uri.parse(raw));
      }
    }

    add(primary);
    // USB / adb reverse builds pin 127.0.0.1 — do not fall back to emulator IP.
    if (primary.contains('127.0.0.1')) {
      return candidates;
    }
    add('http://127.0.0.1:8081');
    add('http://10.0.2.2:8081');
    return candidates;
  }

  Uri resolve(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    final basePath =
        baseUrl.path.endsWith('/') ? baseUrl.path.substring(0, baseUrl.path.length - 1) : baseUrl.path;
    return baseUrl.replace(path: '$basePath$normalized');
  }
}
