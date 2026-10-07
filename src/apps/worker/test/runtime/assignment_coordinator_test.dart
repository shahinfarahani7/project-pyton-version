import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:edgemint_worker/api/worker_api_client.dart';
import 'package:edgemint_worker/api/worker_assignment_models.dart';
import 'package:edgemint_worker/api/worker_routes.dart';
import 'package:edgemint_worker/config/worker_config.dart';
import 'package:edgemint_worker/platform/worker_runtime_channel.dart';
import 'package:edgemint_worker/runtime/assignment_coordinator.dart';
import 'package:edgemint_worker/runtime/assignment_inbox.dart';
import 'package:edgemint_worker/runtime/assignment_receiver.dart';
import 'package:edgemint_worker/runtime/checkpoint_store.dart';
import 'package:edgemint_worker/runtime/device_constraints.dart';
import 'package:edgemint_worker/runtime/device_snapshot.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/runtime/execution_status.dart';
import 'package:edgemint_worker/runtime/inference_adapter.dart';
import 'package:edgemint_worker/runtime/result_submission_outbox.dart';
import 'package:edgemint_worker/runtime/model_artifact_verifier.dart';
import 'package:edgemint_worker/runtime/result_signer.dart';
import 'package:edgemint_worker/runtime/runtime_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

WorkerAssignment sampleAssignment({
  int fenceToken = 3,
  String leaseToken = 'lease-token-1234567890',
}) => WorkerAssignment(
  assignmentId: 'asg_test',
  attemptId: 'att_test',
  revisionId: 'rev_test',
  leaseToken: leaseToken,
  fenceToken: fenceToken,
  leaseExpiresAt: DateTime.parse('2026-12-26T14:00:00Z'),
  taskType: 'document.ocr',
  modelVersionId: 'mdv_test',
  inputManifestUrl: 'https://example/input',
  outputUploadUrl: 'https://example/output',
  startDeadlineAt: DateTime.parse('2026-12-26T13:30:00Z'),
);

const _testSigningKey = 'test-signing-material';

ModelArtifact signedStubModel({
  required String modelVersionId,
  Uint8List? bytes,
  String signingKey = _testSigningKey,
}) {
  final modelBytes = bytes ?? Uint8List.fromList('model'.codeUnits);
  final digest = sha256Hex(modelBytes);
  return ModelArtifact(
    modelVersionId: modelVersionId,
    digestSha256: digest,
    signatureSha256: sha256HexString('$digest:$modelVersionId:$signingKey'),
    backend: InferenceBackend.stub,
    bytes: modelBytes,
  );
}

class _ExecutionMockClient extends http.BaseClient {
  final Map<int, int> progressCalls = {};
  int checkpointCalls = 0;
  int completeCalls = 0;
  int startedCalls = 0;
  int failCalls = 0;
  bool abandonCalled = false;
  int completeHttpStatus = 202;
  final Map<String, int> transportFailuresLeft = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final path = request.url.path;
    if (_consumeTransportFailure(path)) {
      return Future.error(const SocketException('No route to host'));
    }
    if (path.endsWith('/assignments:inboxBootstrap')) {
      return _json(200, {
        'workerDeviceId': 'dev_test',
        'deliveries': <Map<String, dynamic>>[],
      });
    }
    if (path.endsWith('/assignments:next')) {
      return _json(200, sampleAssignment().toJson());
    }
    if (path.endsWith(':started')) {
      startedCalls += 1;
      return _receipt('reportAssignmentStarted');
    }
    if (path.endsWith(':progress')) {
      final body = utf8.decode((request as http.Request).bodyBytes);
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      progressCalls[decoded['sequence'] as int] =
          (progressCalls[decoded['sequence'] as int] ?? 0) + 1;
      return _receipt('progressAssignment');
    }
    if (path.endsWith(':checkpoint')) {
      checkpointCalls += 1;
      return _receipt('checkpointAssignment');
    }
    if (path.endsWith(':complete')) {
      completeCalls += 1;
      if (completeHttpStatus >= 400) {
        return _json(completeHttpStatus, {
          'code': 'ASSIGNMENT_ALREADY_COMPLETE',
        });
      }
      return _receipt('completeAssignment');
    }
    if (path.endsWith(':fail')) {
      failCalls += 1;
      return _receipt('failAssignment');
    }
    if (path.endsWith(':abandon')) {
      abandonCalled = true;
      return _receipt('abandonAssignment');
    }
    if (path.endsWith('/cancellation')) {
      return _json(200, {'cancelled': false});
    }
    return Future.error(UnimplementedError('Unexpected path: $path'));
  }

  bool _consumeTransportFailure(String path) {
    for (final suffix in transportFailuresLeft.keys.toList()) {
      final left = transportFailuresLeft[suffix] ?? 0;
      if (left > 0 && path.endsWith(suffix)) {
        transportFailuresLeft[suffix] = left - 1;
        return true;
      }
    }
    return false;
  }

  Future<http.StreamedResponse> _json(
    int status,
    Map<String, dynamic> payload,
  ) {
    return Future.value(
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(payload))),
        status,
        headers: {'content-type': 'application/json'},
      ),
    );
  }

  Future<http.StreamedResponse> _receipt(String operationId) {
    return _json(202, {
      'operationId': operationId,
      'accepted': true,
      'status': 'accepted',
      'occurredAt': '2026-07-26T12:00:00Z',
    });
  }
}

extension on WorkerAssignment {
  Map<String, dynamic> toJson() => {
    'assignmentId': assignmentId,
    'attemptId': attemptId,
    'revisionId': revisionId,
    'leaseToken': leaseToken,
    'fenceToken': fenceToken,
    'leaseExpiresAt': leaseExpiresAt.toIso8601String(),
    'taskType': taskType,
    'modelVersionId': modelVersionId,
    'inputManifestUrl': inputManifestUrl,
    'outputUploadUrl': outputUploadUrl,
    'assignmentMode': 'auto',
    'executionStartsAutomatically': true,
    'startDeadlineAt': startDeadlineAt.toIso8601String(),
  };
}

void main() {
  test('device constraints block unavailable and offline states', () {
    const constraints = DeviceConstraints();
    expect(
      constraints
          .evaluate(
            const DeviceSnapshot(
              available: false,
              batteryPercent: 90,
              isCharging: true,
              thermalState: ThermalState.normal,
              network: NetworkKind.wifi,
              freeStorageMb: 4096,
              withinSchedule: true,
              consentsGranted: [
                'terms',
                'privacy',
                'resource_use',
                'reward_disclosure',
              ],
            ),
          )
          .allowed,
      isFalse,
    );
    expect(
      constraints
          .evaluate(
            const DeviceSnapshot(
              available: true,
              batteryPercent: 90,
              isCharging: true,
              thermalState: ThermalState.normal,
              network: NetworkKind.offline,
              freeStorageMb: 4096,
              withinSchedule: true,
              consentsGranted: [
                'terms',
                'privacy',
                'resource_use',
                'reward_disclosure',
              ],
            ),
          )
          .allowed,
      isFalse,
    );
  });

  test('checkpoint resume requires matching fence and digests', () async {
    final store = InMemoryEncryptedStore();
    final checkpointStore = CheckpointStore(store);
    final record = CheckpointRecord(
      assignmentId: 'asg_test',
      attemptId: 'att_test',
      fenceToken: 3,
      modelVersionId: 'mdv_test',
      modelDigest: sha256Hex(Uint8List.fromList('model'.codeUnits)),
      inputDigest: sha256Hex(
        Uint8List.fromList('input-for-document.ocr'.codeUnits),
      ),
      sequence: 500,
      progressMilli: 500,
      runtimeStateDigest: sha256Hex(Uint8List.fromList([5])),
      encryptedBlobRef: 'ckpt/asg_test/500',
      savedAt: DateTime.now(),
    );
    await checkpointStore.save(record, Uint8List.fromList([5]));
    final loaded = await checkpointStore.latestFor('asg_test');
    expect(loaded?.progressMilli, 500);
    expect(
      loaded!.canResume(
        activeFenceToken: 3,
        activeModelDigest: sha256Hex(Uint8List.fromList('model'.codeUnits)),
        activeInputDigest: sha256Hex(
          Uint8List.fromList('input-for-document.ocr'.codeUnits),
        ),
      ),
      isTrue,
    );
    expect(
      loaded.canResume(
        activeFenceToken: 4,
        activeModelDigest: sha256Hex(Uint8List.fromList('model'.codeUnits)),
        activeInputDigest: sha256Hex(
          Uint8List.fromList('input-for-document.ocr'.codeUnits),
        ),
      ),
      isFalse,
    );
  });

  test('assignment model bundle uses digest:modelVersionId:signingKey contract', () {
    const verifier = ModelArtifactVerifier();
    final artifact = signedStubModel(modelVersionId: 'mdv_test');
    expect(
      () => verifier.verifyOrThrow(
        artifact: artifact,
        signingKey: _testSigningKey,
      ),
      returnsNormally,
    );
    final legacy = ModelArtifact(
      modelVersionId: 'mdv_test',
      digestSha256: artifact.digestSha256,
      signatureSha256: sha256HexString(
        '${artifact.digestSha256}:$_testSigningKey',
      ),
      backend: InferenceBackend.stub,
      bytes: artifact.bytes,
    );
    expect(
      () => verifier.verifyOrThrow(
        artifact: legacy,
        signingKey: _testSigningKey,
      ),
      throwsA(isA<ModelIntegrityException>()),
    );
  });

  test('inference adapter verifies digest and signature before load', () async {
    final adapter = StubInferenceAdapter();
    final artifact = signedStubModel(modelVersionId: 'mdv_test');
    await adapter.loadVerified(artifact, signingKey: _testSigningKey);
    final output = await adapter.run(
      inputBytes: Uint8List.fromList([1, 2, 3]),
      resumedState: null,
    );
    expect(output.progressMilli, 1000);
  });

  test('result signer produces deterministic signature', () {
    const signer = ResultSigner(signingMaterial: 'secret');
    final first = signer.sign(
      assignmentId: 'asg_test',
      fenceToken: 3,
      resultSha256: 'abc',
      outputArtifactId: 'art_test',
    );
    final second = signer.sign(
      assignmentId: 'asg_test',
      fenceToken: 3,
      resultSha256: 'abc',
      outputArtifactId: 'art_test',
    );
    expect(first, second);
  });

  test(
    'assignment coordinator executes and completes with checkpoints',
    () async {
      final mockHttp = _ExecutionMockClient();
      final api = WorkerApiClient(
        config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8080')),
        httpClient: mockHttp,
      );
      final coordinator = AssignmentCoordinator(
        api: api,
        store: InMemoryEncryptedStore(),
        platform: NoopWorkerRuntimeChannel(material: 'test-signing-material'),
        inference: StubInferenceAdapter(),
      );
      final assignment = await coordinator.pollAssignment();
      expect(assignment, isNotNull);
      await coordinator.executeAssignment(assignment!);
      expect(mockHttp.checkpointCalls, greaterThan(0));
      expect(mockHttp.completeCalls, 1);
      expect(coordinator.status.phase, ExecutionPhase.completed);
    },
  );

  test('polled assignment defers inbox write until execution', () async {
    final store = InMemoryEncryptedStore();
    final coordinator = AssignmentCoordinator(
      api: WorkerApiClient(
        config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8080')),
        httpClient: _ExecutionMockClient(),
      ),
      store: store,
      platform: NoopWorkerRuntimeChannel(material: 'test-signing-material'),
      inference: StubInferenceAdapter(),
    );

    final assignment = await coordinator.pollAssignment();
    final accepted = await coordinator.acceptPolledAssignment(assignment!);

    expect(accepted, same(assignment));
    expect(
      await AssignmentInbox(
        store: store,
      ).latestEntryFor(assignment.assignmentId),
      isNull,
    );
  });

  test('crash-safe resume continues from checkpoint state', () async {
    final store = InMemoryEncryptedStore();
    final checkpointStore = CheckpointStore(store);
    final assignment = sampleAssignment();
    final inputBytes = Uint8List.fromList('input-for-document.ocr'.codeUnits);
    final modelBytes = Uint8List.fromList('model'.codeUnits);
    final modelDigest = sha256Hex(modelBytes);
    final inputDigest = sha256Hex(inputBytes);
    final record = CheckpointRecord(
      assignmentId: assignment.assignmentId,
      attemptId: assignment.attemptId,
      fenceToken: assignment.fenceToken,
      modelVersionId: assignment.modelVersionId,
      modelDigest: modelDigest,
      inputDigest: inputDigest,
      sequence: 500,
      progressMilli: 500,
      runtimeStateDigest: sha256Hex(Uint8List.fromList([5])),
      encryptedBlobRef: 'ckpt/asg_test/500',
      savedAt: DateTime.now(),
    );
    await checkpointStore.save(record, Uint8List.fromList([5]));

    final mockHttp = _ExecutionMockClient();
    final api = WorkerApiClient(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8080')),
      httpClient: mockHttp,
    );
    final coordinator = AssignmentCoordinator(
      api: api,
      store: store,
      platform: NoopWorkerRuntimeChannel(material: 'test-signing-material'),
      inference: StubInferenceAdapter(),
      inputLoader: (_) async => AssignmentInputBundle(
        inputBytes: inputBytes,
        inputDigest: inputDigest,
        modelArtifact: signedStubModel(
          modelVersionId: assignment.modelVersionId,
          bytes: modelBytes,
        ),
      ),
    );
    final resume = await coordinator.inspectResume(
      assignment,
      AssignmentInputBundle(
        inputBytes: inputBytes,
        inputDigest: inputDigest,
        modelArtifact: signedStubModel(
          modelVersionId: assignment.modelVersionId,
          bytes: modelBytes,
        ),
      ),
    );
    expect(resume.startFresh, isFalse);
    await coordinator.executeAssignment(assignment, resume: resume);
    expect(mockHttp.completeCalls, 1);
  });

  test('stale fence fails closed', () async {
    final store = InMemoryEncryptedStore();
    final checkpointStore = CheckpointStore(store);
    final assignment = sampleAssignment(fenceToken: 4);
    final record = CheckpointRecord(
      assignmentId: assignment.assignmentId,
      attemptId: assignment.attemptId,
      fenceToken: 2,
      modelVersionId: assignment.modelVersionId,
      modelDigest: sha256Hex(Uint8List.fromList('model'.codeUnits)),
      inputDigest: sha256Hex(
        Uint8List.fromList('input-for-document.ocr'.codeUnits),
      ),
      sequence: 500,
      progressMilli: 500,
      runtimeStateDigest: sha256Hex(Uint8List.fromList([5])),
      encryptedBlobRef: 'ckpt/asg_test/500',
      savedAt: DateTime.now(),
    );
    await checkpointStore.save(record, Uint8List.fromList([5]));
    final coordinator = AssignmentCoordinator(
      api: WorkerApiClient(
        config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8080')),
        httpClient: http.Client(),
      ),
      store: store,
      platform: NoopWorkerRuntimeChannel(material: 'test-signing-material'),
      inference: StubInferenceAdapter(),
    );
    final bundle = AssignmentInputBundle(
      inputBytes: Uint8List.fromList('input-for-document.ocr'.codeUnits),
      inputDigest: sha256Hex(
        Uint8List.fromList('input-for-document.ocr'.codeUnits),
      ),
      modelArtifact: signedStubModel(modelVersionId: assignment.modelVersionId),
    );
    final decision = await coordinator.inspectResume(assignment, bundle);
    expect(decision.discardedStaleCheckpoint, isTrue);
  });

  test(
    'assignment receiver rejects invalid contract before execution',
    () async {
      final mockHttp = _ExecutionMockClient();
      final api = WorkerApiClient(
        config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8080')),
        httpClient: mockHttp,
      );
      final coordinator = AssignmentCoordinator(
        api: api,
        store: InMemoryEncryptedStore(),
        platform: NoopWorkerRuntimeChannel(material: 'test-signing-material'),
        inference: StubInferenceAdapter(),
      );

      await expectLater(
        coordinator.executeAssignment(sampleAssignment(leaseToken: 'short')),
        throwsA(isA<AssignmentRejectedException>()),
      );

      expect(mockHttp.startedCalls, 0);
      expect(mockHttp.completeCalls, 0);
      expect(mockHttp.failCalls, 1);
      expect(coordinator.status.phase, ExecutionPhase.failed);
    },
  );

  test(
    'assignment receiver rejects missing consent before execution',
    () async {
      final mockHttp = _ExecutionMockClient();
      final api = WorkerApiClient(
        config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8080')),
        httpClient: mockHttp,
      );
      final coordinator = AssignmentCoordinator(
        api: api,
        store: InMemoryEncryptedStore(),
        platform: NoopWorkerRuntimeChannel(
          material: 'test-signing-material',
          snapshot: const DeviceSnapshot(
            available: true,
            batteryPercent: 100,
            isCharging: true,
            thermalState: ThermalState.normal,
            network: NetworkKind.wifi,
            freeStorageMb: 8192,
            withinSchedule: true,
            consentsGranted: ['terms'],
          ),
        ),
        inference: StubInferenceAdapter(),
      );

      await expectLater(
        coordinator.executeAssignment(sampleAssignment()),
        throwsA(isA<AssignmentRejectedException>()),
      );

      expect(mockHttp.startedCalls, 0);
      expect(mockHttp.failCalls, 1);
    },
  );

  test('lease revocation abandons safely', () async {
    final mockHttp = _ExecutionMockClient();
    final api = WorkerApiClient(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8080')),
      httpClient: mockHttp,
    );
    final coordinator = AssignmentCoordinator(
      api: api,
      store: InMemoryEncryptedStore(),
      platform: NoopWorkerRuntimeChannel(material: 'test-signing-material'),
      inference: StubInferenceAdapter(),
    );
    await coordinator.abandon(sampleAssignment(), reason: 'lease_revoked');
    expect(mockHttp.abandonCalled, isTrue);
  });

  test('execution routes match worker API contract', () {
    expect(WorkerRoutes.nextAssignment, '/assignments:next');
    expect(
      WorkerRoutes.completeAssignment('asg_test'),
      '/assignments/asg_test:complete',
    );
    expect(
      WorkerRoutes.executionRoutes,
      [
        WorkerRoutes.nextAssignment,
        WorkerRoutes.assignmentInboxBootstrap,
        WorkerRoutes.renewAssignment('asg_example'),
        WorkerRoutes.reportAssignmentStarted('asg_example'),
        WorkerRoutes.progressAssignment('asg_example'),
        WorkerRoutes.checkpointAssignment('asg_example'),
        WorkerRoutes.completeAssignment('asg_example'),
        WorkerRoutes.failAssignment('asg_example'),
        WorkerRoutes.confirmPhysicalStop('asg_example'),
        WorkerRoutes.abandonAssignment('asg_example'),
      ],
    );
    expect(WorkerRoutes.executionRoutes.length, 10);
  });

  test('progress transport failure does not stop local inference', () async {
    final mockHttp = _ExecutionMockClient()
      ..transportFailuresLeft[':progress'] = 8;
    final store = InMemoryEncryptedStore();
    final inference = _RunCountingInference();
    final coordinator = AssignmentCoordinator(
      api: WorkerApiClient(
        config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8080')),
        httpClient: mockHttp,
      ),
      store: store,
      platform: NoopWorkerRuntimeChannel(material: 'test-signing-material'),
      inference: inference,
    );
    final assignment = await coordinator.pollAssignment();
    await coordinator.executeAssignment(assignment!);
    expect(inference.runs, 1);
    expect(mockHttp.completeCalls, 1);
    expect(mockHttp.failCalls, 0);
    expect(coordinator.status.phase, ExecutionPhase.completed);
    expect(coordinator.status.phase, isNot(ExecutionPhase.failed));
    mockHttp.transportFailuresLeft.clear();
    expect(await coordinator.flushPendingServerSync(), isTrue);
    expect(await coordinator.hasPendingServerSync(), isFalse);
  });

  test('complete transport failure keeps a local result for later sync', () async {
    final mockHttp = _ExecutionMockClient()
      ..transportFailuresLeft[':complete'] = 1;
    final store = InMemoryEncryptedStore();
    final inference = _RunCountingInference();
    final coordinator = AssignmentCoordinator(
      api: WorkerApiClient(
        config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8080')),
        httpClient: mockHttp,
      ),
      store: store,
      platform: NoopWorkerRuntimeChannel(material: 'test-signing-material'),
      inference: inference,
    );
    final assignment = await coordinator.pollAssignment();
    await coordinator.executeAssignment(assignment!);
    expect(coordinator.status.phase, ExecutionPhase.completed);
    expect(coordinator.status.serverSync, ServerSyncState.pending);
    expect(mockHttp.failCalls, 0);
    final pending = await ResultSubmissionOutbox(store: store).pending();
    expect(pending['complete-att_test']?['kind'], 'complete');
    expect(pending['complete-att_test']?['outcome'], 'UNKNOWN_OUTCOME');
    expect(pending['complete-att_test']?['body'], isA<Map>());
    await coordinator.executeAssignment(assignment);
    expect(inference.runs, 1);
    expect(await coordinator.flushPendingServerSync(), isTrue);
    expect(mockHttp.completeCalls, 1);
    expect(await coordinator.hasPendingServerSync(), isFalse);
    expect(coordinator.status.serverSync, ServerSyncState.idle);
  });

  test('failAssignment transport failure stays pending and does not escape', () async {
    final mockHttp = _ExecutionMockClient()..transportFailuresLeft[':fail'] = 1;
    final inference = _RunCountingInference()
      ..failure = StateError('engine crashed');
    final coordinator = AssignmentCoordinator(
      api: WorkerApiClient(
        config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8080')),
        httpClient: mockHttp,
      ),
      store: InMemoryEncryptedStore(),
      platform: NoopWorkerRuntimeChannel(material: 'test-signing-material'),
      inference: inference,
    );
    final assignment = await coordinator.pollAssignment();
    await coordinator.executeAssignment(assignment!);
    expect(coordinator.status.phase, ExecutionPhase.failed);
    expect(coordinator.status.serverSync, ServerSyncState.unknownOutcome);
    expect(mockHttp.failCalls, 0);
    expect(await coordinator.hasPendingServerSync(), isTrue);
    expect(await coordinator.flushPendingServerSync(), isTrue);
    expect(mockHttp.failCalls, 1);
    expect(await coordinator.hasPendingServerSync(), isFalse);
  });

  test('process restart flushes a pending result without running inference', () async {
    final failingHttp = _ExecutionMockClient()
      ..transportFailuresLeft[':complete'] = 1;
    final store = InMemoryEncryptedStore();
    final firstInference = _RunCountingInference();
    final first = AssignmentCoordinator(
      api: WorkerApiClient(
        config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8080')),
        httpClient: failingHttp,
      ),
      store: store,
      platform: NoopWorkerRuntimeChannel(material: 'test-signing-material'),
      inference: firstInference,
    );
    final assignment = await first.pollAssignment();
    await first.executeAssignment(assignment!);
    expect(firstInference.runs, 1);
    expect(first.status.serverSync, ServerSyncState.pending);

    final restartedHttp = _ExecutionMockClient();
    final restartedInference = _RunCountingInference();
    final restarted = AssignmentCoordinator(
      api: WorkerApiClient(
        config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8080')),
        httpClient: restartedHttp,
      ),
      store: store,
      platform: NoopWorkerRuntimeChannel(material: 'test-signing-material'),
      inference: restartedInference,
    );
    expect(await restarted.flushPendingServerSync(), isTrue);
    expect(restartedInference.runs, 0);
    expect(restartedHttp.completeCalls, 1);
    expect(await restarted.hasPendingServerSync(), isFalse);
  });

  test('expired or reassigned lease is not completed again', () async {
    final mockHttp = _ExecutionMockClient();
    final store = InMemoryEncryptedStore();
    final outbox = ResultSubmissionOutbox(store: store);
    await outbox.enqueue('complete-att_test', {
      'kind': 'complete',
      'assignmentId': 'asg_test',
      'leaseExpiresAt': '2020-01-01T00:00:00.000Z',
      'outcome': 'UNKNOWN_OUTCOME',
      'reassigned': false,
      'body': {'resultSha256': 'abc'},
    });
    await outbox.enqueue('complete-reassigned', {
      'kind': 'complete',
      'assignmentId': 'asg_other',
      'leaseExpiresAt': '2099-01-01T00:00:00.000Z',
      'outcome': 'pending',
      'reassigned': true,
      'body': {'resultSha256': 'def'},
    });
    final coordinator = AssignmentCoordinator(
      api: WorkerApiClient(
        config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8080')),
        httpClient: mockHttp,
      ),
      store: store,
      platform: NoopWorkerRuntimeChannel(material: 'test-signing-material'),
      inference: _RunCountingInference(),
    );
    expect(
      await coordinator.flushPendingServerSync(now: DateTime.utc(2026, 1, 1)),
      isTrue,
    );
    expect(mockHttp.completeCalls, 0);
    expect(await coordinator.hasPendingServerSync(), isFalse);
  });

  test('server already completed is acknowledged without another execution', () async {
    final mockHttp = _ExecutionMockClient()..completeHttpStatus = 409;
    final inference = _RunCountingInference();
    final coordinator = AssignmentCoordinator(
      api: WorkerApiClient(
        config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8080')),
        httpClient: mockHttp,
      ),
      store: InMemoryEncryptedStore(),
      platform: NoopWorkerRuntimeChannel(material: 'test-signing-material'),
      inference: inference,
    );
    final assignment = await coordinator.pollAssignment();
    await coordinator.executeAssignment(assignment!);
    expect(coordinator.status.phase, ExecutionPhase.completed);
    expect(mockHttp.failCalls, 0);
    expect(inference.runs, 1);
    await coordinator.executeAssignment(assignment);
    expect(inference.runs, 1);
    expect(await coordinator.hasPendingServerSync(), isFalse);
  });
}

class _RunCountingInference extends StubInferenceAdapter {
  int runs = 0;
  Object? failure;

  @override
  Future<InferenceOutput> run({
    required Uint8List inputBytes,
    required Uint8List? resumedState,
    Future<void> Function(int progressMilli)? onProgress,
    bool Function()? shouldContinue,
  }) async {
    runs += 1;
    final crash = failure;
    if (crash != null) {
      throw crash;
    }
    return super.run(
      inputBytes: inputBytes,
      resumedState: resumedState,
      onProgress: onProgress,
      shouldContinue: shouldContinue,
    );
  }
}
