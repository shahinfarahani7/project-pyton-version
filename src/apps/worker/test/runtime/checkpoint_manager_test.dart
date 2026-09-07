import 'dart:convert';

import 'package:edgemint_worker/inference/llm/hierarchical_summarize_pipeline.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/llm/semantic_chunk_engine.dart';
import 'package:edgemint_worker/runtime/checkpoint_manager.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/runtime/resume_grant.dart';
import 'package:edgemint_worker/runtime/runtime_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/semantic_chunk_golden.dart';

Future<String> _summarizeMockRunner(String prompt) async {
  if (prompt.contains('Combine the partial summaries')) {
    return jsonEncode({
      'summary': 'Final merged summary',
      'keyPoints': ['alpha', 'beta', 'gamma'],
      'missingOrUnclear': [],
    });
  }
  if (prompt.contains('Summarize only this chunk')) {
    final indexMatch = RegExp(r'chunkIndex=(\d+)').firstMatch(prompt);
    final index = indexMatch?.group(1) ?? '0';
    return jsonEncode({
      'summary': 'Partial summary $index',
      'keyPoints': ['point-$index'],
      'missingOrUnclear': [],
    });
  }
  return jsonEncode({
    'summary': 'Direct summary',
    'keyPoints': ['direct'],
    'missingOrUnclear': [],
  });
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
        partialSummary: const {
          'summary': 'Partial summary 0',
          'keyPoints': ['point-0'],
          'missingOrUnclear': [],
        },
      );

      final resume = await manager.loadResumableState(
        assignmentId: 'asg-1',
        activeFenceToken: 4,
        inputHash: plan.inputHash,
      );

      expect(resume, isNotNull);
      expect(resume!.nextChunkIndex, 1);
      expect(resume.completedPartials.single['summary'], 'Partial summary 0');
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
        partialSummary: const {
          'summary': 'Partial summary 0',
          'keyPoints': ['point-0'],
          'missingOrUnclear': [],
        },
      );

      final grant = ResumeGrant(
        grantId: 'grant-1',
        assignmentId: 'asg-consumer',
        activeFenceToken: 7,
        inputDigest: plan.inputHash,
        authorizedChunkIds: {chunk.chunkId},
        modelVersionId: 'mdv_qwen2_5_0_5b',
        runtimeVersion: CheckpointManager.runtimeVersion,
        promptTemplateVersion: '1.0',
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
      expect(resume.completedPartials.single['summary'], 'Partial summary 0');
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
        modelVersionId: 'mdv_qwen2_5_0_5b',
        runtimeVersion: CheckpointManager.runtimeVersion,
        promptTemplateVersion: '1.0',
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
          return _summarizeMockRunner(prompt);
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
        partialSummary: {
          'summary': 'Partial summary 0',
          'keyPoints': ['point-0'],
          'missingOrUnclear': [],
        },
      );

      final result = await processor.runSummarizeJsonTask(
        inputText: input,
        signingKey: 'sign',
        assignmentId: 'asg-resume',
        fenceToken: 9,
      );

      expect(result['summary'], 'Final merged summary');
      expect(calls, plan.totalChunks);
    });
  });
}
