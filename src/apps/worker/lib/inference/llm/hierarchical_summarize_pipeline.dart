import 'dart:convert';

import 'context_budget_manager.dart';
import 'hierarchical_reduce_bounds.dart';
import 'prompt_templates.dart';
import 'semantic_chunk_engine.dart';
import 'semantic_merge_validator.dart';
import 'summarize_reduce_budget.dart';
import 'summarize_task_constraints.dart';
import '../../runtime/checkpoint_manager.dart';
import '../../runtime/resume_grant.dart';

typedef SummarizePromptRunner =
    Future<Map<String, dynamic>> Function(String prompt);
typedef SummarizePipelineLog = void Function(String message);
typedef SummarizePipelineGuard = bool Function();

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
    SummarizeTaskConstraintsV1? constraints,
    SummarizeCheckpointScope? checkpointScope,
    SummarizePipelineGuard? shouldContinue,
  }) async {
    final keyPointCount = constraints?.keyPointCount ?? 3;
    final tracker = ReduceProgressTracker(bounds: _bounds);
    tracker.assertChunkCount(plan.totalChunks);
    _log?.call(
      '[CHUNK PLAN READY] chunks=${plan.totalChunks} inputHash=${plan.inputHash}',
    );

    if (plan.totalChunks <= 1) {
      _log?.call('[CHUNK REQUEST] index=0/1 chars=${inputText.length}');
      final result = await _runPromptJson(
        PromptTemplates.textSummarize(
          sourceText: inputText,
          userInstructions: userInstructions,
          constraints: constraints,
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
      _assertShouldContinue(shouldContinue);
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
          maxKeyPoints: HierarchicalReduceBounds.mapIntermediateMaxKeyPoints,
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
      constraints: constraints,
      shouldContinue: shouldContinue,
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
    SummarizeTaskConstraintsV1? constraints,
    SummarizePipelineGuard? shouldContinue,
  }) async {
    _assertShouldContinue(shouldContinue);
    final progress = tracker ?? ReduceProgressTracker(bounds: _bounds);
    progress.recordDepth(depth);

    if (partials.length == 1) {
      return partials.single;
    }

    final evaluation = SummarizeReduceBudget.evaluate(
      contextBudget: _contextBudget,
      partials: partials,
      userInstructions: userInstructions,
      constraints: constraints,
      maxOutputTokens: _bounds.maxOutputTokensPerStage,
    );
    final partialsJson = jsonEncode(partials);
    _log?.call(
      '[CHUNK REDUCE BUDGET] depth=$depth partials=${partials.length} '
      'partialsChars=${partialsJson.length} '
      'estimatedPromptTokens=${evaluation.formattedPromptTokens} '
      'requiresChunkPipeline=${evaluation.requiresChunkPipeline}',
    );

    if (!evaluation.requiresChunkPipeline) {
      _assertReducePromptFits(evaluation);
      final reducePrompt = PromptTemplates.summarizeReduce(
        partialSummariesJson: partialsJson,
        chunkCount: partials.length,
        userInstructions: userInstructions,
        constraints: constraints,
      );
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
      constraints: constraints,
      shouldContinue: shouldContinue,
    );
    final right = await reducePartials(
      partials.sublist(mid),
      depth: depth + 1,
      tracker: progress,
      userInstructions: userInstructions,
      constraints: constraints,
      shouldContinue: shouldContinue,
    );
    return reducePartials(
      [left, right],
      depth: depth + 1,
      tracker: progress,
      userInstructions: userInstructions,
      constraints: constraints,
      shouldContinue: shouldContinue,
    );
  }

  void _assertShouldContinue(SummarizePipelineGuard? shouldContinue) {
    if (shouldContinue != null && !shouldContinue()) {
      throw HierarchicalReduceExhaustedException(
        reason: 'cancelled_or_deadline_exceeded',
        depth: 0,
        inferenceCalls: 0,
      );
    }
  }

  void _assertReducePromptFits(FormattedPromptEvaluation evaluation) {
    if (evaluation.requiresChunkPipeline) {
      throw HierarchicalReduceExhaustedException(
        reason: 'reduce_prompt_oversized',
        depth: 0,
        inferenceCalls: 0,
      );
    }
  }
}
