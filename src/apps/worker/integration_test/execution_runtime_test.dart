import 'dart:convert';

import 'package:edgemint_worker/api/worker_api_client.dart';
import 'package:edgemint_worker/config/worker_config.dart';
import 'package:edgemint_worker/platform/worker_runtime_channel.dart';
import 'package:edgemint_worker/runtime/assignment_coordinator.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/runtime/execution_status.dart';
import 'package:edgemint_worker/runtime/inference_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _IntegrationMockClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final path = request.url.path;
    if (path.endsWith('/assignments:next')) {
      return _json(200, {
        'assignmentId': 'asg_integration',
        'attemptId': 'att_integration',
        'revisionId': 'rev_integration',
        'leaseToken': 'lease_integration',
        'fenceToken': 1,
        'leaseExpiresAt': '2026-07-26T14:00:00Z',
        'taskType': 'document.ocr',
        'modelVersionId': 'mdv_integration',
        'inputManifestUrl': 'https://example/input',
        'outputUploadUrl': 'https://example/output',
        'assignmentMode': 'auto',
        'executionStartsAutomatically': true,
        'startDeadlineAt': '2026-07-26T13:30:00Z',
      });
    }
    return _json(202, {
      'operationId': 'command',
      'accepted': true,
      'status': 'accepted',
      'occurredAt': '2026-07-26T12:00:00Z',
    });
  }

  Future<http.StreamedResponse> _json(int status, Map<String, dynamic> payload) {
    return Future.value(http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(payload))),
      status,
      headers: {'content-type': 'application/json'},
    ));
  }
}

void main() {
  test('execution runtime integration completes auto-assigned lease', () async {
    final api = WorkerApiClient(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8080')),
      httpClient: _IntegrationMockClient(),
    );
    ExecutionStatus? lastStatus;
    final coordinator = AssignmentCoordinator(
      api: api,
      store: InMemoryEncryptedStore(),
      platform: NoopWorkerRuntimeChannel(material: 'test-signing-material'),
      inference: OnnxInferenceAdapter(),
      onStatus: (status) => lastStatus = status,
    );
    final assignment = await coordinator.pollAssignment();
    expect(assignment, isNotNull);
    await coordinator.executeAssignment(assignment!);
    expect(lastStatus?.phase, ExecutionPhase.completed);
  });
}
