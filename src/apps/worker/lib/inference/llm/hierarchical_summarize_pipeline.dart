import 'dart:convert';

import '../../contracts/worker_error.dart';
import 'context_budget_manager.dart';
import 'evidence_partial_validator.dart';
import 'hierarchical_reduce_bounds.dart';
import 'prompt_templates.dart';
import 'reduce_partial_envelope.dart';
import 'semantic_chunk_engine.dart';
import 'semantic_merge_validator.dart';
import 'summarize_evidence_pipeline.dart';
import 'summarize_evidence_schema.dart';
import 'summarize_inference_stage.dart';
import 'summarize_pipeline_mode.dart';
import 'summarize_reduce_budget.dart';
import 'summarize_task_constraints.dart';
import '../../runtime/checkpoint_manager.dart';
import '../../runtime/resume_grant.dart';

typedef SummarizePromptRunner =
    Future<Map<String, dynamic>> Function(
      String prompt, {
      required SummarizeInferenceStage inferenceStage,
    });
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
    SummarizePipelineMode? mode,
  }) : _contextBudget = contextBudget,
       _runPromptJson = runPromptJson,
       _log = log,
       _bounds = bounds ?? HierarchicalReduceBounds.textSummarizeMapReduce,
       _mode = mode ?? defaultSummarizePipelineMode {
    assertSummarizePipelineModeValid(_mode);
  }

  final ContextBudgetManager _contextBudget;
  final SummarizePromptRunner _runPromptJson;
  final SummarizePipelineLog? _log;
  final HierarchicalReduceBounds _bounds;
  final SummarizePipelineMode _mode;

  bool get _factsOnly => _mode.isFactsOnly;

  String get _checkpointPromptVersion =>
      summarizeCheckpointPromptVersion(factsOnly: _factsOnly);

  String? _lastFinalReduceEvidenceJson;

  /// Exact partials JSON sent to the most recent final Reduce, if any.
  String? get lastFinalReduceEvidenceJson => _lastFinalReduceEvidenceJson;

  static const _mapOutputSaturationRatio = 0.90;

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

    _log?.call(
      '[SUMMARIZE ROUTE] route=${plan.totalChunks <= 1 ? "directPublic" : _mode.multiChunkRouteLabel} '
      'mode=${_mode.logLabel} chunks=${plan.totalChunks} '
      'checkpointPromptVersion=$_checkpointPromptVersion',
    );
    if (plan.totalChunks <= 1) {
      _log?.call('[CHUNK REQUEST] index=0/1 chars=${inputText.length}');
      final result = await _runPromptJson(
        PromptTemplates.textSummarize(
          sourceText: inputText,
          userInstructions: userInstructions,
          constraints: constraints,
        ),
        inferenceStage: SummarizeInferenceStage.directPublic,
      );
      _log?.call('[CHUNK RESPONSE] index=0/1 response=${jsonEncode(result)}');
      return result;
    }

    final envelopes = <ReducePartialEnvelope>[];
    var startIndex = 0;

    if (checkpointScope != null) {
      final resume = await checkpointScope.checkpointManager.loadResumableState(
        assignmentId: checkpointScope.assignmentId,
        activeFenceToken: checkpointScope.fenceToken,
        inputHash: plan.inputHash,
        resumeGrant: checkpointScope.resumeGrant,
        promptVersion: _checkpointPromptVersion,
      );
      if (resume != null) {
        checkpointScope.checkpointManager.assertFenceOnResume(
          activeFenceToken: checkpointScope.fenceToken,
          state: resume,
        );
        for (var index = 0; index < resume.completedPartials.length; index++) {
          final partial = resume.completedPartials[index];
          _validateCheckpointPartial(partial, chunkIndex: index);
          envelopes.add(
            ReducePartialEnvelope.fromMapStage(
              chunk: plan.chunks[index],
              partial: partial,
            ),
          );
        }
        startIndex = resume.nextChunkIndex;
      }
    }

    for (var index = startIndex; index < plan.chunks.length; index++) {
      _assertShouldContinue(shouldContinue);
      final chunk = plan.chunks[index];
      tracker.recordInferenceCall();
      _log?.call(
        '[CHUNK REQUEST] index=${chunk.chunkIndex + 1}/${plan.totalChunks} '
        'chunkId=${chunk.chunkId} '
        'range=${chunk.processedRange.startChar}-${chunk.processedRange.endChar} '
        'sourceChars=${chunk.text.length} '
        'estimatedTokens=${chunk.estimatedTokens} '
        'overlapChars=${chunk.overlapChars} '
        'stage=mapEvidence mode=${_mode.logLabel}',
      );
      final partial = await _runPromptJson(
        PromptTemplates.summarizeMapChunk(
          chunkText: chunk.text,
          chunkIndex: chunk.chunkIndex,
          totalChunks: plan.totalChunks,
          chunkId: chunk.chunkId,
          userInstructions: userInstructions,
          constraints: constraints,
          evidenceTarget: HierarchicalReduceBounds.mapIntermediateEvidenceTarget,
          factsOnly: _factsOnly,
        ),
        inferenceStage: SummarizeInferenceStage.mapEvidence,
      );
      _assertFactsOnlyContract(partial, stageLabel: 'mapEvidence');
      if (_factsOnly) {
        _log?.call(
          '[FACTS ONLY MAP ACCEPTED] index=${chunk.chunkIndex + 1}/${plan.totalChunks} '
          'facts=${(partial['facts'] as List).length}',
        );
      }
      _logMapPartialSaturation(partial);
      _log?.call(
        '[CHUNK RESPONSE] index=${chunk.chunkIndex + 1}/${plan.totalChunks} '
        'chunkId=${chunk.chunkId} response=${jsonEncode(partial)}',
      );
      final envelope = ReducePartialEnvelope.fromMapStage(
        chunk: chunk,
        partial: partial,
      );
      envelopes.add(envelope);

      if (checkpointScope != null) {
        _validateCheckpointPartial(partial, chunkIndex: chunk.chunkIndex);
        final record = await checkpointScope.checkpointManager
            .saveChunkCheckpoint(
              assignmentId: checkpointScope.assignmentId,
              fenceToken: checkpointScope.fenceToken,
              chunk: chunk,
              partialSummary: partial,
              promptVersion: _checkpointPromptVersion,
            );
        if (checkpointScope.onChunkSaved != null) {
          await checkpointScope.onChunkSaved!(record);
        }
      }
    }

    if (SummarizeEvidencePipeline.enabled &&
        envelopes.every(
          (envelope) => SummarizeEvidenceSchema.isEmptyPartial(envelope.partial),
        )) {
      throw WorkerError(
        code: WorkerErrorCode.outputSchemaMismatch,
        message: 'All map evidence partials are empty (map_evidence_all_chunks_empty)',
        retryable: false,
        stage: WorkerTaskStage.llm,
      );
    }

    final result = await reducePartials(
      envelopes,
      tracker: tracker,
      userInstructions: userInstructions,
      constraints: constraints,
      shouldContinue: shouldContinue,
      isFinalMerge: true,
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
    List<ReducePartialEnvelope> envelopes, {
    int depth = 0,
    ReduceProgressTracker? tracker,
    String? userInstructions,
    SummarizeTaskConstraintsV1? constraints,
    SummarizePipelineGuard? shouldContinue,
    bool isFinalMerge = false,
  }) async {
    _assertShouldContinue(shouldContinue);
    final progress = tracker ?? ReduceProgressTracker(bounds: _bounds);
    progress.recordDepth(depth);

    if (envelopes.length == 1) {
      final single = envelopes.single.partial;
      if (isFinalMerge &&
          SummarizeEvidencePipeline.enabled &&
          SummarizeEvidenceSchema.looksLikeEvidencePartial(single)) {
        return _runFinalPublicReduce(
          envelopes: envelopes,
          progress: progress,
          depth: depth,
          userInstructions: userInstructions,
          constraints: constraints,
          shouldContinue: shouldContinue,
        );
      }
      return Map<String, dynamic>.from(single);
    }

    final evaluation = SummarizeReduceBudget.evaluate(
      contextBudget: _contextBudget,
      envelopes: envelopes,
      userInstructions: userInstructions,
      constraints: constraints,
      maxOutputTokens: _bounds.maxOutputTokensPerStage,
      isFinalMerge: isFinalMerge,
      factsOnly: _factsOnly,
    );
    final partialsJson = ReducePartialEnvelope.encodeForPrompt(envelopes);
    _log?.call(
      '[CHUNK REDUCE BUDGET] depth=$depth partials=${envelopes.length} '
      'partialsChars=${partialsJson.length} '
      'estimatedPromptTokens=${evaluation.formattedPromptTokens} '
      'requiresChunkPipeline=${evaluation.requiresChunkPipeline} '
      'isFinalMerge=$isFinalMerge mode=${_mode.logLabel}',
    );

    if (!evaluation.requiresChunkPipeline) {
      _assertReducePromptFits(evaluation);
      final reducePrompt = isFinalMerge
          ? PromptTemplates.summarizeReduceFinal(
              partialSummariesJson: partialsJson,
              chunkCount: envelopes.length,
              userInstructions: userInstructions,
              constraints: constraints,
              factsOnly: _factsOnly,
            )
          : PromptTemplates.summarizeReduceIntermediate(
              partialSummariesJson: partialsJson,
              chunkCount: envelopes.length,
              userInstructions: userInstructions,
              constraints: constraints,
              factsOnly: _factsOnly,
            );
      if (isFinalMerge) {
        _lastFinalReduceEvidenceJson = partialsJson;
      }
      progress.recordInferenceCall();
      _log?.call(
        '[CHUNK REDUCE REQUEST] depth=$depth partials=${envelopes.length} '
        'isFinalMerge=$isFinalMerge '
        'stage=${isFinalMerge ? "finalPublic" : "intermediateEvidence"} '
        'mode=${_mode.logLabel}',
      );
      final merged = await _runPromptJson(
        reducePrompt,
        inferenceStage: isFinalMerge
            ? SummarizeInferenceStage.finalPublic
            : SummarizeInferenceStage.intermediateEvidence,
      );
      if (!isFinalMerge) {
        _assertFactsOnlyContract(merged, stageLabel: 'intermediateEvidence');
      }
      _log?.call(
        '[CHUNK REDUCE RESPONSE] depth=$depth response=${jsonEncode(merged)}',
      );
      SemanticMergeValidator.assertDirectReduceProgress(
        inputPartials: envelopes.map((envelope) => envelope.partial).toList(),
        output: merged,
        minTokenMassReductionRatioMilli:
            _bounds.minTokenMassReductionRatioMilli,
      );
      return merged;
    }

    if (envelopes.length <= 1) {
      throw HierarchicalReduceExhaustedException(
        reason: 'reduce_fan_in_unresolved',
        depth: depth,
        inferenceCalls: progress.inferenceCalls,
      );
    }

    final mid = envelopes.length ~/ 2;
    final leftPartials = await reducePartials(
      envelopes.sublist(0, mid),
      depth: depth + 1,
      tracker: progress,
      userInstructions: userInstructions,
      constraints: constraints,
      shouldContinue: shouldContinue,
      isFinalMerge: false,
    );
    final rightPartials = await reducePartials(
      envelopes.sublist(mid),
      depth: depth + 1,
      tracker: progress,
      userInstructions: userInstructions,
      constraints: constraints,
      shouldContinue: shouldContinue,
      isFinalMerge: false,
    );
    return reducePartials(
      [
        ReducePartialEnvelope.mergeGroup(
          envelopes.sublist(0, mid),
          leftPartials,
        ),
        ReducePartialEnvelope.mergeGroup(
          envelopes.sublist(mid),
          rightPartials,
        ),
      ],
      depth: depth + 1,
      tracker: progress,
      userInstructions: userInstructions,
      constraints: constraints,
      shouldContinue: shouldContinue,
      isFinalMerge: isFinalMerge,
    );
  }

  /// Convenience for tests that pass bare partial maps without chunk metadata.
  Future<Map<String, dynamic>> reduceLegacyPartials(
    List<Map<String, dynamic>> partials, {
    int depth = 0,
    ReduceProgressTracker? tracker,
    String? userInstructions,
    SummarizeTaskConstraintsV1? constraints,
    SummarizePipelineGuard? shouldContinue,
    bool isFinalMerge = true,
  }) =>
      reducePartials(
        ReducePartialEnvelope.wrapLegacyPartials(partials),
        depth: depth,
        tracker: tracker,
        userInstructions: userInstructions,
        constraints: constraints,
        shouldContinue: shouldContinue,
        isFinalMerge: isFinalMerge,
      );

  void _logMapPartialSaturation(Map<String, dynamic> partial) {
    final encodedLength = jsonEncode(partial).length;
    final maxChars =
        (ContextBudgetProfile.qwenBaselineOutputReserveTokens *
                const TokenEstimator().charactersPerToken *
                0.85)
            .floor();
    if (encodedLength >= (maxChars * _mapOutputSaturationRatio).floor()) {
      _log?.call(
        '[MAP OUTPUT SATURATED] encodedChars=$encodedLength maxChars=$maxChars',
      );
    }
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

  Future<Map<String, dynamic>> _runFinalPublicReduce({
    required List<ReducePartialEnvelope> envelopes,
    required ReduceProgressTracker progress,
    required int depth,
    String? userInstructions,
    SummarizeTaskConstraintsV1? constraints,
    SummarizePipelineGuard? shouldContinue,
  }) async {
    _assertShouldContinue(shouldContinue);
    final partialsJson = ReducePartialEnvelope.encodeForPrompt(envelopes);
    final reducePrompt = PromptTemplates.summarizeReduceFinal(
      partialSummariesJson: partialsJson,
      chunkCount: envelopes.length,
      userInstructions: userInstructions,
      constraints: constraints,
      factsOnly: _factsOnly,
    );
    _lastFinalReduceEvidenceJson = partialsJson;
    progress.recordInferenceCall();
    _log?.call(
      '[CHUNK REDUCE REQUEST] depth=$depth partials=${envelopes.length} '
      'isFinalMerge=true stage=finalPublic mode=${_mode.logLabel}',
    );
    final merged = await _runPromptJson(
      reducePrompt,
      inferenceStage: SummarizeInferenceStage.finalPublic,
    );
    _log?.call(
      '[CHUNK REDUCE RESPONSE] depth=$depth response=${jsonEncode(merged)}',
    );
    return merged;
  }

  void _validateCheckpointPartial(
    Map<String, dynamic> partial, {
    required int chunkIndex,
  }) {
    if (!SummarizeEvidencePipeline.enabled) {
      return;
    }
    final issues = EvidencePartialValidator.validate(
      partial: partial,
      generationTruncated: false,
    );
    if (issues.isNotEmpty) {
      throw WorkerError(
        code: WorkerErrorCode.outputSchemaMismatch,
        message:
            'Checkpoint evidence partial invalid at chunk $chunkIndex '
            '(${issues.join('; ')})',
        retryable: false,
        stage: WorkerTaskStage.llm,
      );
    }
    _assertFactsOnlyContract(partial, stageLabel: 'checkpoint[$chunkIndex]');
  }

  /// Facts-only partials keep every statement in facts; a populated
  /// openItems/priority is rejected rather than blanked, so no evidence is lost.
  void _assertFactsOnlyContract(
    Map<String, dynamic> partial, {
    required String stageLabel,
  }) {
    if (!_factsOnly) {
      return;
    }
    final openItems = partial['openItems'];
    final priority = partial['priority'];
    final openCount = openItems is List ? openItems.length : -1;
    final priorityChars = priority is String ? priority.trim().length : -1;
    if (openCount == 0 && priorityChars == 0) {
      return;
    }
    final reason = 'facts_only_contract_mismatch:stage=$stageLabel:'
        'openItems=$openCount:priorityChars=$priorityChars';
    _log?.call('[FACTS ONLY CONTRACT REJECTED] reason=$reason');
    throw WorkerError(
      code: WorkerErrorCode.outputSchemaMismatch,
      message: 'Facts-only evidence rejected ($reason)',
      retryable: false,
      stage: WorkerTaskStage.llm,
    );
  }
}
