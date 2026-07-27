import 'dart:convert';

import 'package:edgemint_worker/api/worker_api_client.dart';
import 'package:edgemint_worker/api/worker_routes.dart';
import 'package:edgemint_worker/config/worker_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _ModelClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  final List<String> paths = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    paths.add(request.url.path);
    if (request.url.path.contains('/manifest')) {
      final payload = jsonEncode({
        'id': 'mdv_test',
        'status': 'active',
        'version': 1,
        'updatedAt': '2026-07-26T12:00:00Z',
      });
      return Future.value(http.StreamedResponse(
        Stream.value(utf8.encode(payload)),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      ));
    }
    if (request.url.path.contains(':report-install')) {
      final payload = jsonEncode({
        'operationId': 'reportModelInstall',
        'accepted': true,
        'status': 'active',
        'occurredAt': '2026-07-26T12:00:00Z',
      });
      return Future.value(http.StreamedResponse(
        Stream.value(utf8.encode(payload)),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      ));
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

void main() {
  test('model delivery client fetches manifest and reports install', () async {
    const token = 'worker-token';
    const digest = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final recording = _ModelClient();
    final client = WorkerApiClient(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8080')),
      httpClient: recording,
    );

    final manifest = await client.getModelManifest(
      modelVersionId: 'mdv_test',
      accessToken: token,
      requestId: 'req-manifest',
    );
    expect(manifest.status, 'active');
    expect(recording.paths.any((path) => path.contains('/models/mdv_test/manifest')), isTrue);

    await client.reportModelInstall(
      modelVersionId: 'mdv_test',
      accessToken: token,
      artifactSha256: digest,
      status: 'active',
      idempotencyKey: 'idem-install',
      requestId: 'req-install',
    );
    expect(
      recording.paths.any((path) => path.contains(WorkerRoutes.reportModelInstall('mdv_test'))),
      isTrue,
    );

    client.close();
    recording.close();
  });
}
