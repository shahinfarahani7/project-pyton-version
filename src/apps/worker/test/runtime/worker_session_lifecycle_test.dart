import 'dart:convert';

import 'package:edgemint_worker/api/worker_api_client.dart';
import 'package:edgemint_worker/config/worker_config.dart';
import 'package:edgemint_worker/platform/worker_runtime_channel.dart';
import 'package:edgemint_worker/runtime/device_snapshot.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/runtime/worker_session_lifecycle.dart';
import 'package:edgemint_worker/runtime/worker_session_store.dart' show WorkerSessionRecord, WorkerSessionStore;
import 'package:edgemint_worker/worker_app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _EnrollmentMockClient extends http.BaseClient {
  _EnrollmentMockClient({
    this.refreshShouldRejectExpired = false,
    this.preferenceUnauthorizedRemaining = 0,
    this.rejectRegistration = false,
  });

  final http.Client _inner = http.Client();
  int registerCalls = 0;
  int refreshCalls = 0;
  int preferenceGets = 0;
  final bool refreshShouldRejectExpired;
  int preferenceUnauthorizedRemaining;
  final bool rejectRegistration;

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
      if (rejectRegistration) {
        return Future.value(_jsonResponse(request, 401, {
          'code': 'AUTH_INVALID_CREDENTIAL',
          'title': 'Invalid credentials',
        }));
      }
      return Future.value(_jsonResponse(request, 201, {
        'workerId': 'wrk_auto',
        'deviceId': 'dev_auto',
        'accessToken': 'token-auto',
        'expiresAt': '2027-07-26T13:00:00Z',
      }));
    }
    if (path.endsWith('/sessions:refresh')) {
      refreshCalls += 1;
      if (refreshShouldRejectExpired) {
        return Future.value(_jsonResponse(request, 401, {
          'code': 'AUTH_INVALID_CREDENTIAL',
          'title': 'Invalid refresh token',
        }));
      }
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
      preferenceGets += 1;
      if (preferenceUnauthorizedRemaining > 0) {
        preferenceUnauthorizedRemaining -= 1;
        return Future.value(_jsonResponse(request, 401, {
          'code': 'AUTH_INVALID_CREDENTIAL',
          'title': 'Invalid credentials',
        }));
      }
      return Future.value(_jsonResponse(request, 200, {
        'version': 1,
        'availability': 'unavailable',
        'networkPolicy': 'wifi_only',
        'chargingPolicy': 'preferred',
        'minimumBatteryPercent': 25,
        'contributionModeId': 'balanced',
        'schedule': {
          'mode': 'always',
          'timezone': 'UTC',
          'windows': <Map<String, dynamic>>[],
        },
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

  test('refreshes near-expiry session without re-registering', () async {
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
      sessionRefreshWindow: const Duration(hours: 1),
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

    await store.writeSession(
      WorkerSessionRecord(
        workerId: 'wrk_auto',
        deviceId: 'dev_auto',
        accessToken: 'token-stale-soon',
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 20)),
        installationId: 'inst_existing',
        benchmarkSubmitted: true,
      ),
    );

    final session = await lifecycle.ensureSession(snapshotOverride: snapshot);
    expect(session.accessToken, 'token-refreshed');
    expect(mock.refreshCalls, 1);
    expect(mock.registerCalls, 0);

    api.close();
    mock.close();
  });

  test('re-registers after expired refresh is rejected', () async {
    final mock = _EnrollmentMockClient(refreshShouldRejectExpired: true);
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

    await store.writeSession(
      WorkerSessionRecord(
        workerId: 'wrk_old',
        deviceId: 'dev_old',
        accessToken: 'token-expired',
        expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
        installationId: 'inst_existing',
        benchmarkSubmitted: true,
      ),
    );

    final session = await lifecycle.ensureSession(snapshotOverride: snapshot);
    expect(session.accessToken, 'token-auto');
    expect(mock.refreshCalls, 1);
    expect(mock.registerCalls, 1);

    api.close();
    mock.close();
  });

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

  Future<WorkerSessionLifecycle> openLifecycle(
    _EnrollmentMockClient mock,
    WorkerSessionStore store,
  ) async {
    final api = WorkerApiClient(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8081')),
      httpClient: mock,
      onAudit: ({required method, required path, required status}) {},
    );
    return WorkerSessionLifecycle(
      api: api,
      store: store,
      platform: NoopWorkerRuntimeChannel(),
    );
  }

  test('valid stored credential is reused without re-enrollment', () async {
    final mock = _EnrollmentMockClient();
    final store = WorkerSessionStore(InMemoryEncryptedStore());
    final lifecycle = await openLifecycle(mock, store);
    await store.writeSession(
      WorkerSessionRecord(
        workerId: 'wrk_auto',
        deviceId: 'dev_auto',
        accessToken: 'token-valid',
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 2)),
        installationId: 'inst_existing',
        benchmarkSubmitted: true,
      ),
    );

    final session = await lifecycle.ensureSession(snapshotOverride: snapshot);
    expect(session.accessToken, 'token-valid');
    expect(mock.registerCalls, 0);
    expect(mock.refreshCalls, 0);
    expect(mock.preferenceGets, 1);

    mock.close();
  });

  test('non-expired server-revoked credential re-enrolls once and retries bootstrap', () async {
    final mock = _EnrollmentMockClient(preferenceUnauthorizedRemaining: 1);
    final store = WorkerSessionStore(InMemoryEncryptedStore());
    final lifecycle = await openLifecycle(mock, store);
    await store.writeSession(
      WorkerSessionRecord(
        workerId: 'wrk_old',
        deviceId: 'dev_old',
        accessToken: 'token-revoked',
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 2)),
        installationId: 'inst_existing',
        benchmarkSubmitted: true,
      ),
    );

    final session = await lifecycle.ensureSession(snapshotOverride: snapshot);
    expect(session.accessToken, 'token-auto');
    expect(mock.registerCalls, 1);
    expect(mock.refreshCalls, 0);
    expect(mock.preferenceGets, 2);
    expect((await store.readSession())?.accessToken, 'token-auto');

    final again = await lifecycle.ensureSession(snapshotOverride: snapshot);
    expect(again.accessToken, 'token-auto');
    expect(mock.registerCalls, 1);

    mock.close();
  });

  test('re-enrollment failure stops without another enrollment attempt', () async {
    final mock = _EnrollmentMockClient(
      preferenceUnauthorizedRemaining: 1,
      rejectRegistration: true,
    );
    final store = WorkerSessionStore(InMemoryEncryptedStore());
    final lifecycle = await openLifecycle(mock, store);
    await store.writeSession(
      WorkerSessionRecord(
        workerId: 'wrk_old',
        deviceId: 'dev_old',
        accessToken: 'token-revoked',
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 2)),
        installationId: 'inst_existing',
        benchmarkSubmitted: true,
      ),
    );

    await expectLater(
      lifecycle.ensureSession(snapshotOverride: snapshot),
      throwsA(isA<WorkerAuthRecoveryFailed>()),
    );
    expect(mock.registerCalls, 1);
    expect(await store.readSession(), isNull);

    mock.close();
  });

  test('bootstrap retry that is still unauthorized does not loop re-enrollment', () async {
    final mock = _EnrollmentMockClient(preferenceUnauthorizedRemaining: 2);
    final store = WorkerSessionStore(InMemoryEncryptedStore());
    final lifecycle = await openLifecycle(mock, store);
    await store.writeSession(
      WorkerSessionRecord(
        workerId: 'wrk_old',
        deviceId: 'dev_old',
        accessToken: 'token-revoked',
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 2)),
        installationId: 'inst_existing',
        benchmarkSubmitted: true,
      ),
    );

    await expectLater(
      lifecycle.ensureSession(snapshotOverride: snapshot),
      throwsA(
        isA<WorkerAuthRecoveryFailed>().having(
          (error) => error.message,
          'message',
          contains('rejected again after re-enrollment'),
        ),
      ),
    );
    expect(mock.registerCalls, 1);
    expect(mock.preferenceGets, 2);
    expect(await store.readSession(), isNull);

    mock.close();
  });

  test('assignment loop does not start before auth is valid', () {
    expect(
      WorkerAssignmentLoopGate.mayStart(available: true, authenticated: false),
      isFalse,
    );
    expect(
      WorkerAssignmentLoopGate.mayStart(available: true, authenticated: true),
      isTrue,
    );
    expect(
      WorkerAssignmentLoopGate.mayStart(available: false, authenticated: true),
      isFalse,
    );

    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:9')),
      encryptedStore: InMemoryEncryptedStore(),
      platform: NoopWorkerRuntimeChannel(),
    );
    addTearDown(controller.dispose);
    expect(controller.workerEnrolled, isFalse);
    controller.startAutoAssignmentLoop();
    expect(controller.debugAssignmentLoopGeneration, 0);

    controller.workerEnrolled = true;
    controller.startAutoAssignmentLoop();
    expect(controller.debugAssignmentLoopGeneration, 1);
    controller.stopAutoAssignmentLoop();
  });
}
