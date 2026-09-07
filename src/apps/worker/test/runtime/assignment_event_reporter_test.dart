import 'dart:convert';

import 'package:edgemint_worker/api/worker_assignment_models.dart';
import 'package:edgemint_worker/inference/llm/semantic_chunk_engine.dart';
import 'package:edgemint_worker/runtime/assignment_event_reporter.dart';
import 'package:edgemint_worker/runtime/checkpoint_manager.dart';
import 'package:edgemint_worker/runtime/execution_plan_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:edgemint_worker/api/worker_api_client.dart';
import 'package:edgemint_worker/config/worker_config.dart';

class _RecordingClient extends http.BaseClient {
  final posts = <({String path, Map<String, dynamic> body, String idempotencyKey})>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST') {
      final body = jsonDecode(await request.finalize().bytesToString()) as Map<String, dynamic>;
      posts.add((
        path: request.url.path,
        body: body,
        idempotencyKey: request.headers['Idempotency-Key'] ?? '',
      ));
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({
          'operationId': 'op_test',
          'accepted': true,
          'status': 'accepted',
          'operation': request.url.path.contains(':checkpoint')
              ? 'checkpointAssignment'
              : 'progressAssignment',
          'occurredAt': '2026-09-02T00:00:00Z',
        }))),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.StreamedResponse(Stream.value([]), 404);
  }
}

WorkerAssignment _assignment() => WorkerAssignment(
      assignmentId: 'asg-events',
      attemptId: 'att-events',
      revisionId: 'rev-events',
      leaseToken: 'lease-events',
      fenceToken: 12,
      leaseExpiresAt: DateTime.parse('2026-12-31T00:00:00Z'),
      taskType: 'text.summarize',
      modelVersionId: 'mdv-qwen',
      inputManifestUrl: 'http://example/manifest',
      outputUploadUrl: 'http://example/output',
      startDeadlineAt: DateTime.parse('2026-12-31T00:00:00Z'),
      taskId: 'tsk-events',
    );

void main() {
  group('AssignmentEventReporter', () {
    test('streams progress with monotonic sequence and fence token', () async {
      final httpClient = _RecordingClient();
      final api = WorkerApiClient(
        config: WorkerConfig(baseUrl: Uri.parse('http://worker.test')),
        httpClient: httpClient,
      );
      final reporter = AssignmentEventReporter(
        api: api,
        assignment: _assignment(),
        accessToken: 'token',
        inputSha256: 'b' * 64,
      );

      await reporter.reportPlanProgress(
        const ExecutionPlanProgressEvent(
          stage: ExecutionPlanStage(
            sequence: 2,
            name: 'llm-map',
            operation: 'llm_map',
            runtimeClass: 'mediapipe_llm',
          ),
          stageIndex: 1,
          stageCount: 5,
          progressMilli: 400,
        ),
      );

      expect(httpClient.posts, hasLength(1));
      final post = httpClient.posts.single;
      expect(post.path, contains(':progress'));
      expect(post.body['fenceToken'], 12);
      expect(post.body['sequence'], 1);
      expect(post.body['stage'], 'llm-map');
      expect(post.body['progressBps'], 4000);
    });

    test('streams chunk checkpoint with fence token and blob ref', () async {
      final httpClient = _RecordingClient();
      final api = WorkerApiClient(
        config: WorkerConfig(baseUrl: Uri.parse('http://worker.test')),
        httpClient: httpClient,
      );
      final reporter = AssignmentEventReporter(
        api: api,
        assignment: _assignment(),
        accessToken: 'token',
        inputSha256: 'c' * 64,
      );

      await reporter.reportChunkCheckpoint(
        ChunkCheckpointRecord(
          assignmentId: 'asg-events',
          fenceToken: 12,
          chunkIndex: 0,
          chunkId: 'chunk-0',
          inputHash: 'input-hash',
          summaryHash: 'd' * 64,
          modelVersionId: 'mdv-qwen',
          runtimeVersion: 'flutter_gemma_mediapipe_v1',
          promptVersion: '1.0',
          processedRange: const ProcessedRange(startChar: 0, endChar: 10),
          partialSummary: const {'summary': 'partial'},
          savedAt: DateTime.parse('2026-09-02T00:00:00Z'),
        ),
      );

      expect(httpClient.posts, hasLength(1));
      final post = httpClient.posts.single;
      expect(post.path, contains(':checkpoint'));
      expect(post.body['fenceToken'], 12);
      expect(post.body['sequence'], 1);
      expect(post.body['checkpointSha256'], 'd' * 64);
      expect(post.body['chunkIndex'], 0);
      expect(post.body['encryptedBlobRef'], contains('chunk_checkpoints/asg-events/0'));
    });
  });
}
