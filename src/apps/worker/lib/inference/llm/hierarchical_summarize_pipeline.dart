import 'dart:convert';

import 'context_budget_manager.dart';
import 'formatted_prompt_builder.dart';
import 'hierarchical_reduce_bounds.dart';
import 'prompt_templates.dart';
import 'semantic_chunk_engine.dart';
import 'semantic_merge_validator.dart';
import '../../runtime/checkpoint_manager.dart';
import '../../runtime/resume_grant.dart';

typedef SummarizePromptRunner =
    Future<Map<String, dynamic>> Function(String prompt);
typedef SummarizePipelineLog = void Function(String message);

class SummarizeCheckpointScope {
  const SummarizeCheckpointScope({
    required this.assignmentId,
    required this.fenceToken,
    required this.checkpointManager,
    this.onChunkSaved,
    this.resumeGrant,
  });

  final String assignmentId;
  final int fenceToken;
  final CheckpointManager checkpointManager;
  final Future<void> Function(ChunkCheckpointRecord record)? onChunkSaved;
  final ResumeGrant? resumeGrant;
}

/// Map/reduce summarization orchestration (Architecture Section 26).
class HierarchicalSummarizePipeline {
  HierarchicalSummarizePipeline({
    required ContextBudgetManager contextBudget,
    required SummarizePromptRunner runPromptJson,
    SummarizePipelineLog? log,
    HierarchicalReduceBounds? bounds,
  }) : _contextBudget = contextBudget,
       _runPromptJson = runPromptJson,
       _log = log,
       _bounds = bounds ?? HierarchicalReduceBounds.textSummarizeMapReduce;

  final ContextBudgetManager _contextBudget;
  final SummarizePromptRunner _runPromptJson;
  final SummarizePipelineLog? _log;
  final HierarchicalReduceBounds _bounds;

  Future<Map<String, dynamic>> summarize({
    required String inputText,
    required ChunkPlan plan,
    String? userInstructions,
    int keyPointCount = 3,
    SummarizeCheckpointScope? checkpointScope,
  }) async {
    final tracker = ReduceProgressTracker(bounds: _bounds);
    tracker.assertChunkCount(plan.totalChunks);
    _log?.call(
      '[CHUNK PLAN READY] chunks=${plan.totalChunks} inputHash=${plan.inputHash}',
    );

    if (plan.totalChunks <= 1) {
      _log?.call('[CHUNK REQUEST] index=0/1 chars=${inputText.length}');
      final result = await _runPromptJson(
        PromptTemplates.documentSummarize(
          ocrText: inputText,
          userInstructions: userInstructions,
          keyPointCount: keyPointCount,
        ),
      );
      _log?.call('[CHUNK RESPONSE] index=0/1 response=${jsonEncode(result)}');
      return result;
    }

    final partials = <Map<String, dynamic>>[];
    var startIndex = 0;

    if (checkpointScope != null) {
      final resume = await checkpointScope.checkpointManager.loadResumableState(
        assignmentId: checkpointScope.assignmentId,
        activeFenceToken: checkpointScope.fenceToken,
        inputHash: plan.inputHash,
        resumeGrant: checkpointScope.resumeGrant,
      );
      if (resume != null) {
        checkpointScope.checkpointManager.assertFenceOnResume(
          activeFenceToken: checkpointScope.fenceToken,
          state: resume,
        );
        partials.addAll(resume.completedPartials);
        startIndex = resume.nextChunkIndex;
      }
    }

    for (var index = startIndex; index < plan.chunks.length; index++) {
      final chunk = plan.chunks[index];
      tracker.recordInferenceCall();
      _log?.call(
        '[CHUNK REQUEST] index=${chunk.chunkIndex + 1}/${plan.totalChunks} '
        'chunkId=${chunk.chunkId} chars=${chunk.text.length}',
      );
      final partial = await _runPromptJson(
        PromptTemplates.summarizeMapChunk(
          chunkText: chunk.text,
          chunkIndex: chunk.chunkIndex,
          totalChunks: plan.totalChunks,
          chunkId: chunk.chunkId,
        ),
      );
      _log?.call(
        '[CHUNK RESPONSE] index=${chunk.chunkIndex + 1}/${plan.totalChunks} '
        'chunkId=${chunk.chunkId} response=${jsonEncode(partial)}',
      );
      partials.add(partial);

      if (checkpointScope != null) {
        final record = await checkpointScope.checkpointManager
            .saveChunkCheckpoint(
              assignmentId: checkpointScope.assignmentId,
              fenceToken: checkpointScope.fenceToken,
              chunk: chunk,
              partialSummary: partial,
            );
        if (checkpointScope.onChunkSaved != null) {
          await checkpointScope.onChunkSaved!(record);
        }
      }
    }

    final result = await reducePartials(
      partials,
      tracker: tracker,
      userInstructions: userInstructions,
      keyPointCount: keyPointCount,
    );
    _log?.call(
      '[CHUNK FINAL RESPONSE] chunks=${plan.totalChunks} '
      'response=${jsonEncode(result)}',
    );
    if (checkpointScope != null) {
      await checkpointScope.checkpointManager.purge(
        checkpointScope.assignmentId,
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> reducePartials(
    List<Map<String, dynamic>> partials, {
    int depth = 0,
    ReduceProgressTracker? tracker,
    String? userInstructions,
    int keyPointCount = 3,
  }) async {
    final progress = tracker ?? ReduceProgressTracker(bounds: _bounds);
    progress.recordDepth(depth);

    if (partials.length == 1) {
      return partials.single;
    }

    final reducePrompt = PromptTemplates.summarizeReduce(
      partialSummariesJson: jsonEncode(partials),
      chunkCount: partials.length,
      userInstructions: userInstructions,
      keyPointCount: keyPointCount,
    );
    final formatted = FormattedPromptBuilder.buildTaskPrompt(
      templateBody: reducePrompt,
      systemInstruction: _contextBudget.defaultSystemInstruction,
    );
    final evaluation = _contextBudget.evaluateFormattedPrompt(
      formattedPrompt: formatted,
      maxOutputTokens: _bounds.maxOutputTokensPerStage,
    );
    if (!evaluation.requiresChunkPipeline) {
      progress.recordInferenceCall();
      _log?.call(
        '[CHUNK REDUCE REQUEST] depth=$depth partials=${partials.length}',
      );
      final merged = await _runPromptJson(reducePrompt);
      _log?.call(
        '[CHUNK REDUCE RESPONSE] depth=$depth response=${jsonEncode(merged)}',
      );
      SemanticMergeValidator.assertDirectReduceProgress(
        inputPartials: partials,
        output: merged,
        minTokenMassReductionRatioMilli:
            _bounds.minTokenMassReductionRatioMilli,
      );
      return merged;
    }

    if (partials.length <= 1) {
      throw HierarchicalReduceExhaustedException(
        reason: 'reduce_fan_in_unresolved',
        depth: depth,
        inferenceCalls: progress.inferenceCalls,
      );
    }

    final mid = partials.length ~/ 2;
    final left = await reducePartials(
      partials.sublist(0, mid),
      depth: depth + 1,
      tracker: progress,
      userInstructions: userInstructions,
      keyPointCount: keyPointCount,
    );
    final right = await reducePartials(
      partials.sublist(mid),
      depth: depth + 1,
      tracker: progress,
      userInstructions: userInstructions,
      keyPointCount: keyPointCount,
    );
    return reducePartials(
      [left, right],
      depth: depth + 1,
      tracker: progress,
      userInstructions: userInstructions,
      keyPointCount: keyPointCount,
    );
  }
}
