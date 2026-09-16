import 'package:edgemint_worker/api/worker_api_client.dart';
import 'package:edgemint_worker/runtime/device_snapshot.dart';
import 'package:edgemint_worker/runtime/worker_heartbeat_service.dart';
import 'package:edgemint_worker/runtime/worker_heartbeat_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('resyncs heartbeat sequence after HEARTBEAT_SEQUENCE_INVALID', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls += 1;
      if (calls == 1) {
        return http.Response(
          '{"code":"HEARTBEAT_SEQUENCE_INVALID","detail":"replay or stale sequence; lastSequence=7"}',
          409,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        '{"operationId":"sendHeartbeat","accepted":true,"status":"accepted","occurredAt":"2026-09-15T07:00:00.000Z"}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = WorkerApiClient(httpClient: client);
    final service = WorkerHeartbeatService(
      api: api,
      workerId: 'wrk_test',
      accessToken: 'token',
      initialSequence: 0,
    );

    const snapshot = DeviceSnapshot(
      available: true,
      batteryPercent: 80,
      isCharging: true,
      thermalState: ThermalState.normal,
      network: NetworkKind.wifi,
      freeStorageMb: 1024,
      withinSchedule: true,
      consentsGranted: ['terms'],
    );

    final sequence = await service.send(
      context: WorkerHeartbeatTelemetryContext(sequence: 0, snapshot: snapshot),
    );

    expect(calls, 2);
    expect(sequence, 8);
    expect(service.sequence, 8);
  });
}
