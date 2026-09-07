import 'package:edgemint_worker/runtime/resume_grant.dart';
import 'package:flutter_test/flutter_test.dart';

ResumeGrant _grant({
  String assignmentId = 'asg-consumer',
  int activeFenceToken = 7,
  String inputDigest = 'abc123',
  Set<String> authorizedChunkIds = const {'chunk-0'},
  String modelVersionId = 'mdv_qwen2_5_0_5b',
  DateTime? expiresAt,
}) =>
    ResumeGrant(
      grantId: 'grant-1',
      assignmentId: assignmentId,
      activeFenceToken: activeFenceToken,
      inputDigest: inputDigest,
      authorizedChunkIds: authorizedChunkIds,
      modelVersionId: modelVersionId,
      runtimeVersion: 'flutter_gemma_mediapipe_v1',
      promptTemplateVersion: '1.0',
      executionPlanVersion: '2026-q3-v1',
      producerFenceToken: 3,
      producerAssignmentId: 'asg-producer',
      expiresAt: expiresAt ?? DateTime.now().toUtc().add(const Duration(hours: 1)),
    );

void main() {
  group('ResumeGrantValidator', () {
    test('permits compatible grant for authorized chunks', () {
      final result = ResumeGrantValidator.evaluate(
        grant: _grant(),
        assignmentId: 'asg-consumer',
        activeFenceToken: 7,
        inputDigest: 'abc123',
        modelVersionId: 'mdv_qwen2_5_0_5b',
        runtimeVersion: 'flutter_gemma_mediapipe_v1',
        promptTemplateVersion: '1.0',
        executionPlanVersion: '2026-q3-v1',
        requestedChunkIds: const ['chunk-0'],
      );
      expect(result.permitted, isTrue);
      expect(result.decision, ResumeCompatibilityDecision.compatible);
    });

    test('rejects expired grant', () {
      final result = ResumeGrantValidator.evaluate(
        grant: _grant(expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1))),
        assignmentId: 'asg-consumer',
        activeFenceToken: 7,
        inputDigest: 'abc123',
        modelVersionId: 'mdv_qwen2_5_0_5b',
        runtimeVersion: 'flutter_gemma_mediapipe_v1',
        promptTemplateVersion: '1.0',
        executionPlanVersion: '2026-q3-v1',
        requestedChunkIds: const ['chunk-0'],
      );
      expect(result.permitted, isFalse);
      expect(result.decision, ResumeCompatibilityDecision.grantExpired);
    });

    test('rejects model-space mismatch', () {
      final result = ResumeGrantValidator.evaluate(
        grant: _grant(modelVersionId: 'mdv_other'),
        assignmentId: 'asg-consumer',
        activeFenceToken: 7,
        inputDigest: 'abc123',
        modelVersionId: 'mdv_qwen2_5_0_5b',
        runtimeVersion: 'flutter_gemma_mediapipe_v1',
        promptTemplateVersion: '1.0',
        executionPlanVersion: '2026-q3-v1',
        requestedChunkIds: const ['chunk-0'],
      );
      expect(result.permitted, isFalse);
      expect(result.decision, ResumeCompatibilityDecision.incompatibleModelSpace);
    });

    test('rejects unauthorized chunk coverage', () {
      final result = ResumeGrantValidator.evaluate(
        grant: _grant(authorizedChunkIds: const {'chunk-0'}),
        assignmentId: 'asg-consumer',
        activeFenceToken: 7,
        inputDigest: 'abc123',
        modelVersionId: 'mdv_qwen2_5_0_5b',
        runtimeVersion: 'flutter_gemma_mediapipe_v1',
        promptTemplateVersion: '1.0',
        executionPlanVersion: '2026-q3-v1',
        requestedChunkIds: const ['chunk-1'],
      );
      expect(result.permitted, isFalse);
      expect(result.decision, ResumeCompatibilityDecision.unauthorizedChunk);
    });
  });
}
