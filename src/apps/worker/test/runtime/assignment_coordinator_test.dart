import 'dart:convert';
import 'dart:typed_data';

import 'package:edgemint_worker/api/worker_api_client.dart';
import 'package:edgemint_worker/api/worker_assignment_models.dart';
import 'package:edgemint_worker/api/worker_routes.dart';
import 'package:edgemint_worker/config/worker_config.dart';
import 'package:edgemint_worker/platform/worker_runtime_channel.dart';
import 'package:edgemint_worker/runtime/assignment_coordinator.dart';
import 'package:edgemint_worker/runtime/checkpoint_store.dart';
import 'package:edgemint_worker/runtime/device_constraints.dart';
import 'package:edgemint_worker/runtime/device_snapshot.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/runtime/execution_status.dart';
import 'package:edgemint_worker/runtime/inference_adapter.dart';
import 'package:edgemint_worker/runtime/result_signer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

WorkerAssignment sampleAssignment({int fenceToken = 3}) => WorkerAssignment(
      assignmentId: 'asg_test',
      attemptId: 'att_test',
      revisionId: 'rev_test',
      leaseToken: 'lease_test',
      fenceToken: fenceToken,
      leaseExpiresAt: DateTime.parse('2026-07-26T14:00:00Z'),
      taskType: 'document.ocr',
      modelVersionId: 'mdv_test',
      inputManifestUrl: 'https://example/input',
      outputUploadUrl: 'https://example/output',
      startDeadlineAt: DateTime.parse('2026-07-26T13:30:00Z'),
    );

class _ExecutionMockClient extends http.BaseClient {
  final Map<int, int> progressCalls = {};
  int checkpointCalls = 0;
  int completeCalls = 0;
  bool abandonCalled = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final path = request.url.path;
    if (path.endsWith('/assignments:next')) {
      return _json(200, sampleAssignment().toJson());
    }
    if (path.endsWith(':started')) {
      return _receipt('reportAssignmentStarted');
    }
    if (path.endsWith(':progress')) {
      final body = utf8.decode((request as http.Request).bodyBytes);
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      progressCalls[decoded['sequence'] as int] = (progressCalls[decoded['sequence'] as int] ?? 0) + 1;
      return _receipt('progressAssignment');
    }
    if (path.endsWith(':checkpoint')) {
      checkpointCalls += 1;
      return _receipt('checkpointAssignment');
    }
    if (path.endsWith(':complete')) {
      completeCalls += 1;
      return _receipt('completeAssignment');
    }
    if (path.endsWith(':abandon')) {
      abandonCalled = true;
      return _receipt('abandonAssignment');
    }
    return Future.error(UnimplementedError('Unexpected path: $path'));
  }

  Future<http.StreamedResponse> _json(int status, Map<String, dynamic> payload) {
    return Future.value(http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(payload))),
      status,
      headers: {'content-type': 'application/json'},
    ));
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
      constraints.evaluate(const DeviceSnapshot(
        available: false,
        batteryPercent: 90,
        isCharging: true,
        thermalState: ThermalState.normal,
        network: NetworkKind.wifi,
        freeStorageMb: 4096,
        withinSchedule: true,
        consentsGranted: ['terms', 'privacy', 'resource_use', 'reward_disclosure'],
      )).allowed,
      isFalse,
    );
    expect(
      constraints.evaluate(const DeviceSnapshot(
        available: true,
        batteryPercent: 90,
        isCharging: true,
        thermalState: ThermalState.normal,
        network: NetworkKind.offline,
        freeStorageMb: 4096,
        withinSchedule: true,
        consentsGranted: ['terms', 'privacy', 'resource_use', 'reward_disclosure'],
      )).allowed,
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
      inputDigest: sha256Hex(Uint8List.fromList('input-for-document.ocr'.codeUnits)),
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
        activeInputDigest: sha256Hex(Uint8List.fromList('input-for-document.ocr'.codeUnits)),
      ),
      isTrue,
    );
    expect(
      loaded.canResume(
        activeFenceToken: 4,
        activeModelDigest: sha256Hex(Uint8List.fromList('model'.codeUnits)),
        activeInputDigest: sha256Hex(Uint8List.fromList('input-for-document.ocr'.codeUnits)),
      ),
      isFalse,
    );
  });

  test('inference adapter verifies digest and signature before load', () async {
    final adapter = StubInferenceAdapter();
    final artifact = ModelArtifact(
      modelVersionId: 'mdv_test',
      digestSha256: sha256Hex(Uint8List.fromList('model'.codeUnits)),
      signatureSha256: sha256HexString('${sha256Hex(Uint8List.fromList('model'.codeUnits))}:test-signing-material'),
      backend: InferenceBackend.stub,
      bytes: Uint8List.fromList('model'.codeUnits),
    );
    await adapter.loadVerified(artifact, signingKey: 'test-signing-material');
    final output = await adapter.run(inputBytes: Uint8List.fromList([1, 2, 3]), resumedState: null);
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

  test('assignment coordinator executes and completes with checkpoints', () async {
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
        modelArtifact: ModelArtifact(
          modelVersionId: assignment.modelVersionId,
          digestSha256: modelDigest,
          signatureSha256: sha256HexString('$modelDigest:test-signing-material'),
          backend: InferenceBackend.stub,
          bytes: modelBytes,
        ),
      ),
    );
    final resume = await coordinator.inspectResume(
      assignment,
      AssignmentInputBundle(
        inputBytes: inputBytes,
        inputDigest: inputDigest,
        modelArtifact: ModelArtifact(
          modelVersionId: assignment.modelVersionId,
          digestSha256: modelDigest,
          signatureSha256: sha256HexString('$modelDigest:test-signing-material'),
          backend: InferenceBackend.stub,
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
      inputDigest: sha256Hex(Uint8List.fromList('input-for-document.ocr'.codeUnits)),
      sequence: 500,
      progressMilli: 500,
      runtimeStateDigest: sha256Hex(Uint8List.fromList([5])),
      encryptedBlobRef: 'ckpt/asg_test/500',
      savedAt: DateTime.now(),
    );
    await checkpointStore.save(record, Uint8List.fromList([5]));
    final coordinator = AssignmentCoordinator(
      api: WorkerApiClient(config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8080')), httpClient: http.Client()),
      store: store,
      platform: NoopWorkerRuntimeChannel(material: 'test-signing-material'),
      inference: StubInferenceAdapter(),
    );
    final bundle = AssignmentInputBundle(
      inputBytes: Uint8List.fromList('input-for-document.ocr'.codeUnits),
      inputDigest: sha256Hex(Uint8List.fromList('input-for-document.ocr'.codeUnits)),
      modelArtifact: ModelArtifact(
        modelVersionId: assignment.modelVersionId,
        digestSha256: sha256Hex(Uint8List.fromList('model'.codeUnits)),
        signatureSha256: sha256HexString('${sha256Hex(Uint8List.fromList('model'.codeUnits))}:test-signing-material'),
        backend: InferenceBackend.stub,
        bytes: Uint8List.fromList('model'.codeUnits),
      ),
    );
    final decision = await coordinator.inspectResume(assignment, bundle);
    expect(decision.discardedStaleCheckpoint, isTrue);
  });

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
    expect(WorkerRoutes.completeAssignment('asg_test'), '/assignments/asg_test:complete');
    expect(WorkerRoutes.executionRoutes.length, 7);
  });
}
