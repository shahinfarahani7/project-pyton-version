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
}
