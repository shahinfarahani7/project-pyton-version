import 'dart:convert';

import 'package:edgemint_worker/api/worker_api_client.dart';
import 'package:edgemint_worker/api/worker_routes.dart';
import 'package:edgemint_worker/config/worker_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _RecordingClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  final List<String> paths = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    paths.add(request.url.path);
    if (request.url.path.endsWith('/auth/challenges')) {
      final payload = jsonEncode({
        'challengeId': '11111111-1111-1111-1111-111111111111',
        'nonce': 'nonce-test',
        'expiresAt': '2026-07-26T12:00:00Z',
      });
      return Future.value(http.StreamedResponse(
        Stream.value(utf8.encode(payload)),
        201,
        headers: {'content-type': 'application/json'},
        request: request,
      ));
    }
    if (request.url.path.endsWith('/workers/register')) {
      final payload = jsonEncode({
        'workerId': 'wrk_test',
        'deviceId': 'dev_test',
        'accessToken': 'token-test',
        'expiresAt': '2026-07-26T13:00:00Z',
      });
      return Future.value(http.StreamedResponse(
        Stream.value(utf8.encode(payload)),
        201,
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
  test('enrollment client calls canonical challenge and register routes', () async {
    final recording = _RecordingClient();
    final client = WorkerApiClient(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8080')),
      httpClient: recording,
    );

    final challenge = await client.createDeviceChallenge(
      installationId: 'install-test',
      idempotencyKey: 'idem-challenge',
      requestId: 'req-challenge',
    );
    expect(challenge.nonce, 'nonce-test');
    expect(recording.paths.any((path) => path.contains(WorkerRoutes.createChallenge)), isTrue);

    final registration = await client.registerWorkerDevice(
      idempotencyKey: 'idem-register',
      requestId: 'req-register',
      payload: <String, dynamic>{
        'installationId': 'install-test',
        'platform': 'android',
        'appVersion': '5.0.0',
        'capabilities': <String, dynamic>{},
        'attestation': <String, dynamic>{
          'challengeId': challenge.challengeId,
          'nonce': challenge.nonce,
        },
      },
    );
    expect(registration.workerId, 'wrk_test');
    expect(recording.paths.any((path) => path.contains(WorkerRoutes.registerDevice)), isTrue);

    client.close();
    recording.close();
  });
}
