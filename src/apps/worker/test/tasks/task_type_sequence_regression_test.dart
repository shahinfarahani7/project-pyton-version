import 'dart:convert';
import 'dart:typed_data';

import 'package:edgemint_worker/api/worker_assignment_models.dart';
import 'package:edgemint_worker/contracts/worker_error.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/ocr/fake_ocr_engine.dart';
import 'package:edgemint_worker/runtime/execution_plan_runner.dart';
import 'package:edgemint_worker/runtime/model_runtime_manager.dart';
import 'package:edgemint_worker/api/worker_api_client.dart';
import 'package:edgemint_worker/config/worker_config.dart';
import 'package:edgemint_worker/platform/worker_runtime_channel.dart';
import 'package:edgemint_worker/runtime/device_snapshot.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/runtime/worker_session_lifecycle.dart';
import 'package:edgemint_worker/runtime/worker_session_store.dart';
import 'package:edgemint_worker/tasks/task_execution_engine.dart';
import 'package:edgemint_worker/runtime/inference_adapter.dart';
import 'package:edgemint_worker/tasks/task_type_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

Uint8List _onePixelPng() => Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      ),
    );

WorkerAssignment _assignment({
  required String assignmentId,
  required String taskType,
  required int fenceToken,
  required String taskId,
}) {
  return WorkerAssignment(
    assignmentId: assignmentId,
    attemptId: 'att-$assignmentId',
    revisionId: 'rev-$assignmentId',
    leaseToken: 'lease-$assignmentId',
    fenceToken: fenceToken,
    leaseExpiresAt: DateTime.parse('2026-12-31T00:00:00Z'),
    taskType: taskType,
    modelVersionId: 'mdv_qwen3_0_6b',
    inputManifestUrl: 'http://example/manifest',
    outputUploadUrl: 'http://example/output',
    startDeadlineAt: DateTime.parse('2026-12-31T00:00:00Z'),
    taskId: taskId,
  );
}

TaskExecutionContext _ocrContext({
  required WorkerAssignment assignment,
  String idempotencyKey = 'ocr-key',
}) {
  return TaskExecutionContext(
    assignment: assignment,
    manifest: {
      'schemaVersion': '1.0',
      'idempotencyKey': idempotencyKey,
      'options': {'minOcrConfidence': 0.5},
    },
    inputBytes: _onePixelPng(),
    isImageInput: true,
  );
}

TaskExecutionContext _classifyContext({
  required WorkerAssignment assignment,
  String idempotencyKey = 'cls-key',
}) {
  const text = 'Your verification code is 123456';
  return TaskExecutionContext(
    assignment: assignment,
    manifest: {
      'schemaVersion': '1.0',
      'idempotencyKey': idempotencyKey,
      'inputText': text,
      'options': {'allowedLabels': ['payment', 'other']},
    },
    inputBytes: Uint8List.fromList(utf8.encode(text)),
    isImageInput: false,
  );
}

void main() {
  group('Cross-type execution sequence', () {
    test('A OCR → B classify → A OCR reuses OCR engine without stale assignment binding', () async {
      final ocr = FakeOcrEngine();
      final memory = InMemoryModelRuntimeManager(verifyArtifact: false);
      final runner = ExecutionPlanRunner(modelRuntime: memory);
      var classifyCalls = 0;
      final engine = TaskExecutionEngine(
        ocrEngine: ocr,
        qwenProcessor: QwenTaskProcessor(
          runner: (_) async {
            classifyCalls += 1;
            return '{"label":"payment","confidence":0.88,"evidence":["code"]}';
          },
        ),
        executionPlanRunner: runner,
      );

      final first = await engine.execute(
        context: _ocrContext(
          assignment: _assignment(
            assignmentId: 'asg-a1',
            taskType: 'document.ocr',
            fenceToken: 1,
            taskId: 'tsk-a1',
          ),
          idempotencyKey: 'seq-a1',
        ),
        signingKey: 'sign',
        freeStorageMb: 8192,
      );
      expect(first.metrics['taskStatus'], 'succeeded');
      expect(engine.lastResult?.output?['rawText'], isNotEmpty);
      expect(classifyCalls, 0);
      expect(ocr.recognizeCalls, 1);

      await engine.execute(
        context: _classifyContext(
          assignment: _assignment(
            assignmentId: 'asg-b1',
            taskType: 'text.classify',
            fenceToken: 2,
            taskId: 'tsk-b1',
          ),
          idempotencyKey: 'seq-b1',
        ),
        signingKey: 'sign',
        freeStorageMb: 8192,
      );
      expect(classifyCalls, 1);
      expect(engine.lastResult?.output?['data']?['label'], 'payment');
      expect(runner.boundAssignmentId, isNull);

      final third = await engine.execute(
        context: _ocrContext(
          assignment: _assignment(
            assignmentId: 'asg-a2',
            taskType: 'document.ocr',
            fenceToken: 3,
            taskId: 'tsk-a2',
          ),
          idempotencyKey: 'seq-a2',
        ),
        signingKey: 'sign',
        freeStorageMb: 8192,
      );
      expect(third.metrics['taskStatus'], 'succeeded');
      expect(ocr.recognizeCalls, 2);
      expect(runner.boundAssignmentId, isNull);
      expect(engine.lastResult?.output?['rawText'], isNotEmpty);
    });

    test('after cancelled classify, following OCR succeeds without extra LLM calls', () async {
      final ocr = FakeOcrEngine();
      var classifyCalls = 0;
      final engine = TaskExecutionEngine(
        ocrEngine: ocr,
        qwenProcessor: QwenTaskProcessor(
          runner: (_) async {
            classifyCalls += 1;
            return '{"label":"payment","confidence":0.88,"evidence":["code"]}';
          },
        ),
      );

      await engine.execute(
        context: _classifyContext(
          assignment: _assignment(
            assignmentId: 'asg-cancel',
            taskType: 'text.classify',
            fenceToken: 10,
            taskId: 'tsk-cancel',
          ),
          idempotencyKey: 'cancel-b',
        ),
        signingKey: 'sign',
        freeStorageMb: 8192,
        isCancelled: () => true,
      );
      expect(engine.lastResult?.status.name, isNot('succeeded'));
      expect(classifyCalls, 0);

      final recovery = await engine.execute(
        context: _ocrContext(
          assignment: _assignment(
            assignmentId: 'asg-recover',
            taskType: 'document.ocr',
            fenceToken: 11,
            taskId: 'tsk-recover',
          ),
          idempotencyKey: 'recover-a',
        ),
        signingKey: 'sign',
        freeStorageMb: 8192,
      );
      expect(recovery.metrics['taskStatus'], 'succeeded');
      expect(ocr.recognizeCalls, 1);
      expect(classifyCalls, 0);
    });

    test('after classify LLM failure, following OCR succeeds', () async {
      final ocr = FakeOcrEngine();
      var classifyCalls = 0;
      final engine = TaskExecutionEngine(
        ocrEngine: ocr,
        qwenProcessor: QwenTaskProcessor(
          runner: (_) async {
            classifyCalls += 1;
            return 'not-json';
          },
        ),
      );

      await engine.execute(
        context: _classifyContext(
          assignment: _assignment(
            assignmentId: 'asg-fail',
            taskType: 'text.classify',
            fenceToken: 20,
            taskId: 'tsk-fail',
          ),
          idempotencyKey: 'fail-b',
        ),
        signingKey: 'sign',
        freeStorageMb: 8192,
      );
      expect(classifyCalls, greaterThanOrEqualTo(1));
      expect(engine.lastResult?.status.name, isNot('succeeded'));

      final recovery = await engine.execute(
        context: _ocrContext(
          assignment: _assignment(
            assignmentId: 'asg-after-fail',
            taskType: 'document.ocr',
            fenceToken: 21,
            taskId: 'tsk-after-fail',
          ),
          idempotencyKey: 'after-fail-a',
        ),
        signingKey: 'sign',
        freeStorageMb: 8192,
      );
      expect(recovery.metrics['taskStatus'], 'succeeded');
      expect(ocr.recognizeCalls, 1);
    });

    test('unknown task type fails explicitly without touching OCR', () async {
      final ocr = FakeOcrEngine();
      final engine = TaskExecutionEngine(
        ocrEngine: ocr,
        qwenProcessor: QwenTaskProcessor(
          runner: (_) async => '{}',
        ),
      );

      await engine.execute(
        context: TaskExecutionContext(
          assignment: _assignment(
            assignmentId: 'asg-unknown',
            taskType: 'totally.unsupported.task',
            fenceToken: 99,
            taskId: 'tsk-unknown',
          ),
          manifest: const {
            'schemaVersion': '1.0',
            'idempotencyKey': 'unknown',
            'inputText': 'hello',
          },
          inputBytes: Uint8List.fromList(utf8.encode('hello')),
          isImageInput: false,
        ),
        signingKey: 'sign',
        freeStorageMb: 8192,
      );

      expect(engine.lastResult?.error?.code, WorkerErrorCode.unsupportedTaskType);
      expect(ocr.recognizeCalls, 0);
    });

    test('single TaskExecutionEngine instance runs A→B→A without concurrent guard lock', () async {
      final ocr = FakeOcrEngine();
      final engine = TaskExecutionEngine(
        ocrEngine: ocr,
        qwenProcessor: QwenTaskProcessor(
          runner: (_) async =>
              '{"label":"payment","confidence":0.88,"evidence":["code"]}',
        ),
      );
      final engineIdentity = identityHashCode(engine);

      for (final id in ['seq-1', 'seq-2', 'seq-3']) {
        final isClassify = id == 'seq-2';
        await engine.execute(
          context: isClassify
              ? _classifyContext(
                  assignment: _assignment(
                    assignmentId: 'asg-$id',
                    taskType: 'text.classify',
                    fenceToken: id.hashCode.abs() % 1000,
                    taskId: 'tsk-$id',
                  ),
                  idempotencyKey: id,
                )
              : _ocrContext(
                  assignment: _assignment(
                    assignmentId: 'asg-$id',
                    taskType: 'document.ocr',
                    fenceToken: id.hashCode.abs() % 1000,
                    taskId: 'tsk-$id',
                  ),
                  idempotencyKey: id,
                ),
          signingKey: 'sign',
          freeStorageMb: 8192,
        );
        expect(identityHashCode(engine), engineIdentity);
      }
      expect(ocr.recognizeCalls, 2);
    });

    test('worker auth session is reused while TaskExecutionEngine runs consecutive tasks', () async {
      final mock = _SequenceEnrollmentClient();
      final api = WorkerApiClient(
        config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8081')),
        httpClient: mock,
        onAudit: ({required method, required path, required status}) {},
      );
      final lifecycle = WorkerSessionLifecycle(
        api: api,
        store: WorkerSessionStore(InMemoryEncryptedStore()),
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

      await lifecycle.ensureSession(snapshotOverride: snapshot);
      expect(mock.registerCalls, 1);

      final engine = TaskExecutionEngine(
        ocrEngine: FakeOcrEngine(),
        qwenProcessor: QwenTaskProcessor(
          runner: (_) async =>
              '{"label":"payment","confidence":0.88,"evidence":["code"]}',
        ),
      );
      await engine.execute(
        context: _ocrContext(
          assignment: _assignment(
            assignmentId: 'asg-auth-a',
            taskType: 'document.ocr',
            fenceToken: 40,
            taskId: 'tsk-auth-a',
          ),
        ),
        signingKey: 'sign',
        freeStorageMb: 8192,
      );
      await engine.execute(
        context: _classifyContext(
          assignment: _assignment(
            assignmentId: 'asg-auth-b',
            taskType: 'text.classify',
            fenceToken: 41,
            taskId: 'tsk-auth-b',
          ),
        ),
        signingKey: 'sign',
        freeStorageMb: 8192,
      );

      await lifecycle.ensureSession(snapshotOverride: snapshot);
      expect(mock.registerCalls, 1);
      api.close();
      mock.close();
    });

    test('ExecutionPlanRunner reuses resident model and closes sessions after classify plan', () async {
      final memory = InMemoryModelRuntimeManager(verifyArtifact: false);
      await memory.ensureResident(
        artifact: ModelArtifact(
          modelVersionId: 'mdv-qwen',
          digestSha256: 'digest',
          signatureSha256: 'sig',
          backend: InferenceBackend.liteRt,
          bytes: Uint8List.fromList([1]),
        ),
        signingKey: 'sign',
      );
      final runner = ExecutionPlanRunner(modelRuntime: memory);
      final assignment = _assignment(
        assignmentId: 'asg-plan',
        taskType: 'text.classify',
        fenceToken: 50,
        taskId: 'tsk-plan',
      );
      await runner.runPlan(
        plan: ExecutionPlanCatalog.forTaskType(TaskTypeMapper.textClassify),
        assignment: assignment,
        executeStage: (_) async => 'ok',
      );
      expect(memory.loadCount, 1);
      expect(memory.sessionCount, 1);
      expect(memory.openSessionCount, 0);
      expect(runner.boundAssignmentId, isNull);
    });
  });
}

class _SequenceEnrollmentClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  int registerCalls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final path = request.url.path;
    if (path.endsWith('/auth/challenges')) {
      return Future.value(_jsonResponse(request, 201, {
        'challengeId': '11111111-1111-1111-1111-111111111111',
        'nonce': 'nonce-test',
        'expiresAt': '2027-07-26T12:00:00Z',
      }));
    }
    if (path.endsWith('/workers/register')) {
      registerCalls += 1;
      return Future.value(_jsonResponse(request, 201, {
        'workerId': 'wrk_seq',
        'deviceId': 'dev_seq',
        'accessToken': 'token-seq',
        'expiresAt': '2027-07-26T13:00:00Z',
      }));
    }
    if (path.endsWith('/sessions:refresh')) {
      return Future.value(_jsonResponse(request, 200, {
        'workerId': 'wrk_seq',
        'deviceId': 'dev_seq',
        'accessToken': 'token-seq-refreshed',
        'expiresAt': '2027-07-26T14:00:00Z',
      }));
    }
    if (path.contains('/benchmark')) {
      return Future.value(_jsonResponse(request, 200, {
        'operationId': 'submitBenchmark',
        'accepted': true,
        'status': 'ready',
        'occurredAt': '2026-07-26T12:01:00Z',
        'resourceId': 'wrk_seq',
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
        'resourceId': 'wrk_seq',
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
