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
    return baseUrl.replace(path: '$basePath$normalized', query: null, fragment: null);
  }

  /// Rewrites dev portal task input/output URLs to a host the worker device can reach.
  ///
  /// Backend embeds [EDGEMINT_DEV_API_PUBLIC_URL] (often a LAN IP). Android emulators
  /// must use `10.0.2.2:8080`; USB/adb-reverse builds use `127.0.0.1:8080`.
  static Uri resolveDevServiceUrl({
    required Uri workerGatewayBaseUrl,
    required String embeddedServiceUrl,
  }) {
    final parsed = Uri.parse(embeddedServiceUrl);
    if (!parsed.path.contains('/v1/dev/worker/')) {
      return parsed;
    }

    final workerHost = workerGatewayBaseUrl.host;
    final localHost = switch (workerHost) {
      'localhost' => '127.0.0.1',
      '10.0.2.2' || '127.0.0.1' => workerHost,
      _ => null,
    };
    if (localHost != null && parsed.host != localHost) {
      return parsed.replace(host: localHost, port: 8080);
    }

    if (parsed.host == '127.0.0.1' || parsed.host == 'localhost') {
      final host = workerHost == 'localhost' ? '127.0.0.1' : workerHost;
      return parsed.replace(host: host, port: 8080);
    }

    return parsed;
  }

  /// True when [candidate] exposes worker enrollment routes (not just /health/live).
  static bool workerApiProbeStatusAcceptable(int statusCode) {
    return statusCode != 404;
  }
}
