import 'package:edgemint_worker/config/worker_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolve preserves host and appends route path', () {
    final config = WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8081'));
    expect(
      config.resolve('/auth/challenges').toString(),
      'http://127.0.0.1:8081/auth/challenges',
    );
  });

  test('resolve handles trailing slash base path', () {
    final config = WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8081/'));
    expect(
      config.resolve('/workers/register').toString(),
      'http://127.0.0.1:8081/workers/register',
    );
  });

  test('worker api probe treats 404 as missing enrollment route', () {
    expect(WorkerConfig.workerApiProbeStatusAcceptable(404), isFalse);
    expect(WorkerConfig.workerApiProbeStatusAcceptable(422), isTrue);
    expect(WorkerConfig.workerApiProbeStatusAcceptable(201), isTrue);
  });

  test('resolveDevServiceUrl rewrites LAN api-gateway URL for emulator', () {
    final resolved = WorkerConfig.resolveDevServiceUrl(
      workerGatewayBaseUrl: Uri.parse('http://10.0.2.2:8081'),
      embeddedServiceUrl:
          'http://172.20.34.71:8080/v1/dev/worker/tasks/tsk_dev_abc/input',
    );
    expect(
      resolved.toString(),
      'http://10.0.2.2:8080/v1/dev/worker/tasks/tsk_dev_abc/input',
    );
  });

  test('resolveDevServiceUrl keeps LAN URL for physical device on same network', () {
    const embedded =
        'http://172.20.34.71:8080/v1/dev/worker/tasks/tsk_dev_abc/input';
    final resolved = WorkerConfig.resolveDevServiceUrl(
      workerGatewayBaseUrl: Uri.parse('http://172.20.34.71:8081'),
      embeddedServiceUrl: embedded,
    );
    expect(resolved.toString(), embedded);
  });
}
