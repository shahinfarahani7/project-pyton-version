import 'dart:async';
import 'dart:convert';

import 'package:edgemint_worker/config/worker_config.dart';
import 'package:edgemint_worker/platform/worker_runtime_channel.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/worker_app_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// One failed health check used to latch `backendOnline` off. Heartbeats kept
/// running, so the phone looked online, but the assignment loop never polled
/// again.
void main() {
  test('assignment loop polls again after a failed health check', () async {
    final client = _AssignmentLoopClient();
    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:9')),
      httpClient: client,
      encryptedStore: InMemoryEncryptedStore(),
      platform: NoopWorkerRuntimeChannel(),
    );
    addTearDown(controller.dispose);

    controller.assignmentPollInterval = const Duration(milliseconds: 20);
    controller.backendOnline = true;
    controller.modelPhase = ModelInstallPhase.ready;
    controller.workerEnrolled = true;
    controller.updateWorkerAccessToken('dev-token');
    controller.startAutoAssignmentLoop();

    await client.secondPoll.future.timeout(const Duration(seconds: 5));
    expect(client.nextCalls, greaterThanOrEqualTo(2));
    expect(client.healthCalls, greaterThanOrEqualTo(3));
  });

  test('resume restarts a dead assignment loop while availability stays on', () async {
    final client = _AssignmentLoopClient(failSecondHealth: false);
    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:9')),
      httpClient: client,
      encryptedStore: InMemoryEncryptedStore(),
      platform: NoopWorkerRuntimeChannel(),
    );
    addTearDown(controller.dispose);

    controller.assignmentPollInterval = const Duration(milliseconds: 20);
    controller.backendOnline = true;
    controller.modelPhase = ModelInstallPhase.ready;
    controller.workerEnrolled = true;
    controller.updateWorkerAccessToken('dev-token');
    controller.startAutoAssignmentLoop();
    expect(controller.debugAssignmentLoopGeneration, 1);

    controller.available = false;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(controller.debugAssignmentLoopGeneration, 1);

    controller.available = true;
    controller.handleAppLifecycleState(AppLifecycleState.resumed);
    await client.secondPoll.future.timeout(const Duration(seconds: 5));
    expect(controller.debugAssignmentLoopGeneration, 2);
  });

  test('a heartbeat asks for work without reopening the app', () async {
    final client = _AssignmentLoopClient(failSecondHealth: false);
    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:9')),
      httpClient: client,
      encryptedStore: InMemoryEncryptedStore(),
      platform: NoopWorkerRuntimeChannel(),
    );
    addTearDown(controller.dispose);

    controller.assignmentPollInterval = const Duration(milliseconds: 20);
    controller.backendOnline = true;
    controller.modelPhase = ModelInstallPhase.ready;
    controller.workerEnrolled = false;
    controller.available = true;
    controller.debugAdoptLiveSession(
      workerId: 'wrk_live',
      accessToken: 'dev-token',
    );

    expect(controller.debugAssignmentLoopGeneration, 0);
    controller.debugHeartbeatTick();

    await client.firstPoll.future.timeout(const Duration(seconds: 5));
    expect(client.nextCalls, greaterThanOrEqualTo(1));
    expect(controller.debugAssignmentLoopGeneration, greaterThanOrEqualTo(1));
  });

  test('a heartbeat does not poll while the worker is turned off', () async {
    final client = _AssignmentLoopClient(failSecondHealth: false);
    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:9')),
      httpClient: client,
      encryptedStore: InMemoryEncryptedStore(),
      platform: NoopWorkerRuntimeChannel(),
    );
    addTearDown(controller.dispose);

    controller.backendOnline = true;
    controller.modelPhase = ModelInstallPhase.ready;
    controller.workerEnrolled = true;
    controller.available = false;
    controller.debugAdoptLiveSession(
      workerId: 'wrk_live',
      accessToken: 'dev-token',
    );
    controller.debugHeartbeatTick();

    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(client.nextCalls, 0);
    expect(controller.debugAssignmentLoopGeneration, 0);
  });
}

class _AssignmentLoopClient extends http.BaseClient {
  _AssignmentLoopClient({this.failSecondHealth = true});

  final bool failSecondHealth;
  int healthCalls = 0;
  int nextCalls = 0;
  final Completer<void> firstPoll = Completer<void>();
  final Completer<void> secondPoll = Completer<void>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.endsWith('/health/live')) {
      healthCalls += 1;
      if (failSecondHealth && healthCalls == 2) {
        throw http.ClientException('backend blip', request.url);
      }
      return _response(request, 200, 'ok');
    }
    if (path.contains('assignments')) {
      nextCalls += 1;
      if (nextCalls >= 1 && !firstPoll.isCompleted) {
        firstPoll.complete();
      }
      if (nextCalls >= 2 && !secondPoll.isCompleted) {
        secondPoll.complete();
      }
      return _response(request, 204, '');
    }
    return _response(request, 204, '');
  }

  http.StreamedResponse _response(
    http.BaseRequest request,
    int status,
    String body,
  ) {
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      status,
      request: request,
    );
  }
}
