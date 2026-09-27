import 'package:edgemint_worker/inference/llm/prompt_templates.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/llm/semantic_chunk_engine.dart';
import 'package:edgemint_worker/inference/llm/summarize_evidence_pipeline.dart';
import 'package:edgemint_worker/models/worker_model_catalog.dart';
import 'package:edgemint_worker/runtime/checkpoint_manager.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/runtime/resume_grant.dart';
import 'package:edgemint_worker/runtime/runtime_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/summarize_contract_mock_runner.dart';
import 'fixtures/semantic_chunk_golden.dart';

Map<String, dynamic> checkpointPartialForChunk(int index) {
  if (SummarizeEvidencePipeline.enabled) {
    return {
      'schemaVersion': '2',
      'facts': ['point-$index'],
      'openItems': <String>[],
      'priority': '',
    };
  }
  return {
    'summary': 'Partial summary $index',
    'keyPoints': ['point-$index'],
    'missingOrUnclear': <String>[],
  };
}

void main() {
  group('CheckpointManager', () {
    test('resume reuses completed chunk checkpoints with matching fence', () async {
      final store = InMemoryEncryptedStore();
      final manager = CheckpointManager(store);
      const engine = SemanticChunkEngine();
      final input = semanticChunkGoldenInput();
      final plan = engine.chunk(input);
      assumeTrue(plan.totalChunks > 1);

      await manager.saveChunkCheckpoint(
        assignmentId: 'asg-1',
        fenceToken: 4,
        chunk: plan.chunks.first,
        partialSummary: checkpointPartialForChunk(0),
      );

      final resume = await manager.loadResumableState(
        assignmentId: 'asg-1',
        activeFenceToken: 4,
        inputHash: plan.inputHash,
      );

      expect(resume, isNotNull);
      expect(resume!.nextChunkIndex, 1);
      if (SummarizeEvidencePipeline.enabled) {
        expect(resume.completedPartials.single['facts'], ['point-0']);
      } else {
        expect(resume.completedPartials.single['summary'], 'Partial summary 0');
      }
    });

    test('stale fence invalidates saved chunk checkpoints', () async {
      final store = InMemoryEncryptedStore();
      final manager = CheckpointManager(store);
      const engine = SemanticChunkEngine();
      final plan = engine.chunk(semanticChunkGoldenInput());

      await manager.saveChunkCheckpoint(
        assignmentId: 'asg-2',
        fenceToken: 2,
        chunk: plan.chunks.first,
        partialSummary: const {'summary': 'saved'},
      );

      final resume = await manager.loadResumableState(
        assignmentId: 'asg-2',
        activeFenceToken: 3,
        inputHash: plan.inputHash,
      );

      expect(resume, isNull);
    });

    test('cross-assignment resume uses ResumeGrant without matching active fence', () async {
      final store = InMemoryEncryptedStore();
      final manager = CheckpointManager(store);
      const engine = SemanticChunkEngine();
      final plan = engine.chunk(semanticChunkGoldenInput());
      final chunk = plan.chunks.first;

      await manager.saveChunkCheckpoint(
        assignmentId: 'asg-producer',
        fenceToken: 3,
        chunk: chunk,
        partialSummary: checkpointPartialForChunk(0),
      );

      final grant = ResumeGrant(
        grantId: 'grant-1',
        assignmentId: 'asg-consumer',
        activeFenceToken: 7,
        inputDigest: plan.inputHash,
        authorizedChunkIds: {chunk.chunkId},
        modelVersionId: WorkerModelCatalog.modelVersionId,
        runtimeVersion: CheckpointManager.runtimeVersion,
        promptTemplateVersion: PromptTemplates.version,
        executionPlanVersion: '2026-q3-v1',
        producerFenceToken: 3,
        producerAssignmentId: 'asg-producer',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );

      final resume = await manager.loadResumableState(
        assignmentId: 'asg-consumer',
        activeFenceToken: 7,
        inputHash: plan.inputHash,
        resumeGrant: grant,
      );

      expect(resume, isNotNull);
      expect(resume!.nextChunkIndex, 1);
      expect(resume.fenceToken, 7);
      if (SummarizeEvidencePipeline.enabled) {
        expect(resume.completedPartials.single['facts'], ['point-0']);
      } else {
        expect(resume.completedPartials.single['summary'], 'Partial summary 0');
      }
    });

    test('cross-assignment resume rejects unauthorized chunk coverage', () async {
      final store = InMemoryEncryptedStore();
      final manager = CheckpointManager(store);
      const engine = SemanticChunkEngine();
      final plan = engine.chunk(semanticChunkGoldenInput());

      await manager.saveChunkCheckpoint(
        assignmentId: 'asg-producer',
        fenceToken: 3,
        chunk: plan.chunks.first,
        partialSummary: const {'summary': 'saved'},
      );

      final grant = ResumeGrant(
        grantId: 'grant-2',
        assignmentId: 'asg-consumer',
        activeFenceToken: 7,
        inputDigest: plan.inputHash,
        authorizedChunkIds: const {'chunk-not-saved'},
        modelVersionId: WorkerModelCatalog.modelVersionId,
        runtimeVersion: CheckpointManager.runtimeVersion,
        promptTemplateVersion: PromptTemplates.version,
        executionPlanVersion: '2026-q3-v1',
        producerFenceToken: 3,
        producerAssignmentId: 'asg-producer',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );

      expect(
        () => manager.loadResumableState(
          assignmentId: 'asg-consumer',
          activeFenceToken: 7,
          inputHash: plan.inputHash,
          resumeGrant: grant,
        ),
        throwsA(isA<ResumeGrantRejectedException>()),
      );
    });

    test('assertFenceOnResume rejects mismatched fence token', () {
      final manager = CheckpointManager(InMemoryEncryptedStore());
      expect(
        () => manager.assertFenceOnResume(
          activeFenceToken: 5,
          state: const ChunkCheckpointResumeState(
            completedPartials: [],
            nextChunkIndex: 1,
            inputHash: 'hash',
            fenceToken: 4,
          ),
        ),
        throwsA(isA<StaleFenceException>()),
      );
    });
  });

  group('HierarchicalSummarizePipeline resume', () {
    test('resumes map stage after simulated crash', () async {
      final store = InMemoryEncryptedStore();
      final checkpointManager = CheckpointManager(store);
      var calls = 0;
      final processor = QwenTaskProcessor(
        runner: (prompt) async {
          calls += 1;
          return summarizeContractMockRunner(prompt);
        },
        checkpointManager: checkpointManager,
      );
      final input = semanticChunkGoldenInput();
      final plan = processor.planInputChunks(input);
      assumeTrue(plan.totalChunks > 1);

      await checkpointManager.saveChunkCheckpoint(
        assignmentId: 'asg-resume',
        fenceToken: 9,
        chunk: plan.chunks.first,
        partialSummary: checkpointPartialForChunk(0),
      );

      final result = await processor.runSummarizeJsonTask(
        inputText: input,
        signingKey: 'sign',
        assignmentId: 'asg-resume',
        fenceToken: 9,
      );

      expect(result['summary'], 'Final merged summary');
      final remainingChunks = plan.totalChunks - 1;
      expect(calls, inInclusiveRange(remainingChunks + 1, remainingChunks + 2));
    });
  });
}
