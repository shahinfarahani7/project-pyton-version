import 'dart:convert';

import 'package:edgemint_worker/api/worker_api_client.dart';
import 'package:edgemint_worker/config/worker_config.dart';
import 'package:edgemint_worker/platform/worker_runtime_channel.dart';
import 'package:edgemint_worker/runtime/device_snapshot.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/runtime/worker_session_lifecycle.dart';
import 'package:edgemint_worker/runtime/worker_session_store.dart' show WorkerSessionRecord, WorkerSessionStore;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _EnrollmentMockClient extends http.BaseClient {
  _EnrollmentMockClient();

  final http.Client _inner = http.Client();
  int registerCalls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final path = request.url.path;
    if (path.endsWith('/auth/challenges')) {
      return Future.value(_jsonResponse(request, 201, {
        'challengeId': '11111111-1111-1111-1111-111111111111',
        'nonce': 'nonce-test',
        'expiresAt': '2026-07-26T12:00:00Z',
      }));
    }
    if (path.endsWith('/workers/register')) {
      registerCalls += 1;
      return Future.value(_jsonResponse(request, 201, {
        'workerId': 'wrk_auto',
        'deviceId': 'dev_auto',
        'accessToken': 'token-auto',
        'expiresAt': '2026-07-26T13:00:00Z',
      }));
    }
    if (path.endsWith('/sessions:refresh')) {
      return Future.value(_jsonResponse(request, 200, {
        'workerId': 'wrk_auto',
        'deviceId': 'dev_auto',
        'accessToken': 'token-refreshed',
        'expiresAt': '2026-07-26T14:00:00Z',
      }));
    }
    if (path.contains('/benchmark')) {
      return Future.value(_jsonResponse(request, 200, {
        'operationId': 'submitBenchmark',
        'accepted': true,
        'status': 'ready',
        'occurredAt': '2026-07-26T12:01:00Z',
        'resourceId': 'wrk_auto',
      }));
    }
    if (path.endsWith('/worker-preferences') && request.method == 'GET') {
      return Future.value(_jsonResponse(request, 200, {
        'version': 1,
        'availability': 'unavailable',
        'networkPolicy': 'wifi_only',
        'chargingPolicy': 'preferred',
        'minimumBatteryPercent': 25,
        'contributionModeId': 'balanced',
        'schedule': {'mode': 'always', 'timezone': 'UTC', 'windows': []},
      }));
    }
    if (path.endsWith('/worker-preferences') && request.method == 'PUT') {
      return Future.value(_jsonResponse(request, 200, {
        'operationId': 'replaceWorkerPreferences',
        'accepted': true,
        'status': 'accepted',
        'occurredAt': '2026-07-26T12:01:00Z',
        'resourceId': 'wrk_auto',
      }));
    }
    return _inner.send(request);
  }

  http.StreamedResponse _jsonResponse(
    http.BaseRequest request,
    int status,
    Map<String, dynamic> body,
  ) {
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }

  @override
  void close() => _inner.close();
}

void main() {
  test('ensureSession enrolls, benchmarks, and persists credentials', () async {
    final mock = _EnrollmentMockClient();
    final api = WorkerApiClient(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8081')),
      httpClient: mock,
      onAudit: ({required method, required path, required status}) {},
    );
    final store = WorkerSessionStore(InMemoryEncryptedStore());
    final lifecycle = WorkerSessionLifecycle(
      api: api,
      store: store,
      platform: NoopWorkerRuntimeChannel(),
    );

    const snapshot = DeviceSnapshot(
      available: true,
      batteryPercent: 100,
      isCharging: true,
      isEmulator: true,
      isX86Android: true,
      thermalState: ThermalState.normal,
      network: NetworkKind.wifi,
      freeStorageMb: 4096,
      withinSchedule: true,
      consentsGranted: ['terms', 'privacy', 'resource_use', 'reward_disclosure'],
    );

    final session = await lifecycle.ensureSession(snapshotOverride: snapshot);
    expect(session.workerId, 'wrk_auto');
    expect(session.accessToken, 'token-auto');
    expect(session.benchmarkSubmitted, isTrue);
    expect(mock.registerCalls, 1);

    final persisted = await store.readSession();
    expect(persisted?.workerId, 'wrk_auto');
    expect(persisted?.benchmarkSubmitted, isTrue);

    final reused = await lifecycle.ensureSession(snapshotOverride: snapshot);
    expect(reused.accessToken, 'token-auto');
    expect(mock.registerCalls, 1);

    api.close();
    mock.close();
  });

  test('WorkerSessionRecord round-trips through encrypted store', () async {
    final store = WorkerSessionStore(InMemoryEncryptedStore());
    final record = WorkerSessionRecord(
      workerId: 'wrk_test',
      deviceId: 'dev_test',
      accessToken: 'token-test',
      expiresAt: DateTime.utc(2026, 7, 26, 13),
      installationId: 'inst_test',
      benchmarkSubmitted: true,
    );
    await store.writeSession(record);
    final loaded = await store.readSession();
    expect(loaded?.workerId, record.workerId);
    expect(loaded?.accessToken, record.accessToken);
    expect(loaded?.benchmarkSubmitted, isTrue);
  });
}
