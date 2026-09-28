import 'dart:convert';
import 'dart:typed_data';

import '../../contracts/worker_error.dart';
import '../../models/worker_model_catalog.dart';
import '../../runtime/gemma_inference_adapter.dart';
import '../../runtime/inference_adapter.dart';
import '../../runtime/checkpoint_manager.dart';
import '../../runtime/encrypted_store.dart';
import '../../runtime/model_runtime_manager.dart';
import '../../runtime/worker_content_diagnostics.dart';
import '../../validation/json_output_validator.dart';
import 'context_budget_manager.dart';
import 'formatted_prompt_builder.dart';
import 'evidence_partial_validator.dart';
import 'hierarchical_reduce_bounds.dart';
import 'hierarchical_summarize_pipeline.dart';
import 'labeled_summary_parser.dart';
import 'map_partial_validator.dart';
import 'output_limit_enforcer.dart';
import 'prompt_templates.dart';
import 'semantic_chunk_engine.dart';
import 'summarize_chunk_experiment.dart';
import 'summarize_evidence_pipeline.dart';
import 'summarize_evidence_schema.dart';
import 'summarize_diagnostic_map.dart';
import 'diagnostic/summarize_map_evidence_diagnostic_fixture.dart';
import 'diagnostic/facts_only_experiment.dart';
import 'diagnostic/summarize_map_prompt_variant.dart';
import 'summarize_inference_stage.dart';
import 'summarize_output_normalizer.dart';
import 'summarize_output_validator.dart';
import 'summarize_pipeline_mode.dart';
import 'summarize_task_constraints.dart';

class QwenInferenceConfig {
  const QwenInferenceConfig({
    this.contextSize = ContextBudgetProfile.qwenBaselineTotalContextTokens,
    this.maxOutputTokens = WorkerModelCatalog.outputReserveTokens,
    this.temperature = 0.1,
    this.topP = 0.8,
    this.topK = 20,
    this.repeatPenalty = 1.05,
  });

  final int contextSize;
  final int maxOutputTokens;
  final double temperature;
  final double topP;
  final int topK;
  final double repeatPenalty;
}

typedef LlmRunner = Future<String> Function(String prompt);
typedef QwenPipelineLog = void Function(String message);

/// A model reply plus whether the runtime stop cut it at the output budget.
class _PromptReply {
  const _PromptReply({
    required this.text,
    required this.truncated,
    this.stopReason = 'model_eos',
  });

  final String text;
  final bool truncated;
  final String stopReason;
}

/// One shared budget for JSON repair, labeled fallback, compact, and constraint repair.
class CorrectiveInferenceBudget {
  CorrectiveInferenceBudget({this.maxCalls = 1});

  final int maxCalls;
  var used = 0;

  bool get hasRemaining => used < maxCalls;

  bool consume() {
    if (!hasRemaining) {
      return false;
    }
    used += 1;
    return true;
  }
}

class QwenTaskProcessor {
  QwenTaskProcessor({
    GemmaLiteRtInferenceAdapter? adapter,
    LlmRunner? runner,
    ContextBudgetManager? contextBudget,
    SemanticChunkEngine? chunkEngine,
    CheckpointManager? checkpointManager,
    OutputLimitEnforcer? outputLimitEnforcer,
    this.log,
    this.config = const QwenInferenceConfig(),
    this.testRunnerTruncated = false,
    this.testRunnerStopReason = 'output_limit',
  }) : _adapter = adapter ?? GemmaLiteRtInferenceAdapter(),
       _runner = runner,
       _contextBudget = contextBudget ?? const ContextBudgetManager(),
       _chunkEngine = chunkEngine ?? const SemanticChunkEngine(),
       _checkpointManager = checkpointManager,
       _outputLimitEnforcer =
           outputLimitEnforcer ?? const OutputLimitEnforcer();

  final GemmaLiteRtInferenceAdapter _adapter;
  final LlmRunner? _runner;
  final ContextBudgetManager _contextBudget;
  final SemanticChunkEngine _chunkEngine;
  final CheckpointManager? _checkpointManager;
  final OutputLimitEnforcer _outputLimitEnforcer;
  final QwenPipelineLog? log;
  final QwenInferenceConfig config;

  /// Test-only: when [runner] is set, mark replies truncated to exercise adapter stop paths.
  final bool testRunnerTruncated;
  final String testRunnerStopReason;

  static const _minKeyPoints = 3;
  static const _minRepairExcerptChars = 400;
  static const _mapIntermediateEvidenceTarget =
      HierarchicalReduceBounds.mapIntermediateEvidenceTarget;

  static const _summaryOutputSchema = <String, String>{
    'summary': 'string',
    'keyPoints': 'array',
    'mainComplaint': 'string',
    'suggestedImprovement': 'string',
    'missingOrUnclear': 'array',
  };

  ModelRuntimeManager get modelRuntimeManager => _adapter.runtimeManager;
  bool get requiresNativeRuntime => _runner == null;

  ContextBudgetManager get contextBudget => _contextBudget;

  SemanticChunkEngine get chunkEngine => _chunkEngine;

  ChunkPlan planInputChunks(
    String inputText, {
    int? reservedPromptTokens,
    int? experimentalSourceChunkTokenCap,
  }) =>
      _chunkEngine.chunk(
        inputText,
        reservedPromptTokens: reservedPromptTokens,
        experimentalSourceChunkTokenCap: experimentalSourceChunkTokenCap,
      );

  void _log(String message) => log?.call(message);

  String _preview(String value, {int maxLength = 1200}) {
    final normalized = value.replaceAll('\n', r'\n');
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength)}…';
  }

  Future<void> ensureLoaded({required String signingKey}) async {
    // Another task may have activated InternVL; always re-select the exact
    // verified Qwen artifact before text generation.
    await _adapter.loadVerified(
      ModelArtifact(
        modelVersionId: WorkerModelCatalog.modelVersionId,
        digestSha256: WorkerModelCatalog.installedDigestMarker,
        signatureSha256: WorkerModelCatalog.installedAttestationSignature(
          signingKey,
        ),
        backend: InferenceBackend.liteRt,
        bytes: Uint8List.fromList([0]),
      ),
      signingKey: signingKey,
    );
  }

  Future<void> ensureRuntimeResident({required String signingKey}) async {
    if (_runner != null) {
      return;
    }
    await ensureLoaded(signingKey: signingKey);
  }

  Future<Map<String, dynamic>> runJsonTask({
    required String prompt,
    SummarizeInferenceStage inferenceStage = SummarizeInferenceStage.genericJson,
    Map<String, dynamic>? outputSchema,
    required String signingKey,
    int maxArrayItems = 3,
    bool labeledFallback = false,
    CorrectiveInferenceBudget? correctiveBudget,
  }) async {
    final policy = SummarizeStagePolicy.forStage(inferenceStage);
    final stageLabel = policy.logLabel;
    WorkerContentDiagnostics.logInferencePrompt(stage: stageLabel, prompt: prompt);
    _log(
      '[MODEL REQUEST] stage=$stageLabel promptChars=${prompt.length} '
      'prompt="${_preview(prompt)}"',
    );
    final reply = await _runPromptReply(prompt, signingKey: signingKey);
    WorkerContentDiagnostics.logInferenceResponse(
      stage: stageLabel,
      raw: reply.text,
      stopReason: reply.stopReason,
      truncated: reply.truncated,
    );
    _log(
      '[MODEL RESPONSE] stage=$stageLabel responseChars=${reply.text.length} '
      'truncated=${reply.truncated} stopReason=${reply.stopReason} '
      'response="${_preview(reply.text)}"',
    );
    final parsed = await _parseJsonResponse(
      raw: reply.text,
      outputSchema: outputSchema,
      signingKey: signingKey,
      maxArrayItems: maxArrayItems,
      truncated: reply.truncated,
      stopReason: reply.stopReason,
      inferenceStage: inferenceStage,
      policy: policy,
      sourcePrompt: labeledFallback && policy.allowLabeledFallback ? prompt : null,
      correctiveBudget: correctiveBudget,
    );
    if (inferenceStage == SummarizeInferenceStage.mapEvidence) {
      _assertUsableMapPartial(
        partial: parsed,
        generationTruncated: reply.truncated,
        stopReason: reply.stopReason,
        policy: policy,
      );
    } else if (inferenceStage == SummarizeInferenceStage.intermediateEvidence) {
      _assertUsableEvidencePartial(
        partial: parsed,
        generationTruncated: reply.truncated,
        stopReason: reply.stopReason,
        stageLabel: stageLabel,
      );
    }
    return parsed;
  }

  Future<Map<String, dynamic>> runSummarizeJsonTask({
    required String inputText,
    String? userInstructions,
    required String signingKey,
    Map<String, dynamic>? outputSchema,
    SummarizeTaskConstraintsV1? constraints,
    String? assignmentId,
    int? fenceToken,
    Future<void> Function(ChunkCheckpointRecord record)? onChunkCheckpoint,
    bool Function()? isCancelled,
    SummarizePipelineMode? pipelineMode,
    String? taskId,
  }) async {
    final mode = pipelineMode ?? defaultSummarizePipelineMode;
    assertSummarizePipelineModeValid(mode);
    final factsOnly = mode.isFactsOnly;
    final instructions = resolveSummarizeInstructions(userInstructions);
    final keyPointCount = constraints?.keyPointCount ?? _minKeyPoints;
    _assertInstructionsFitOrThrow(
      instructions: instructions,
      constraints: constraints,
    );
    _assertMapPromptFitsOrThrow(
      instructions: instructions,
      constraints: constraints,
      factsOnly: factsOnly,
    );
    SummarizeChunkExperiment.assertValidConfigurationOrThrow();
    _log(
      '[SUMMARIZE TASK START] taskId=${taskId ?? "unknown"} '
      'mode=${mode.logLabel} evidenceV2=${SummarizeEvidencePipeline.enabled} '
      'sourceChars=${inputText.length} '
      'sourceSha256=${sha256HexString(inputText)} '
      'options=${jsonEncode(constraints?.toJson())} '
      'checkpointPromptVersion=${summarizeCheckpointPromptVersion(factsOnly: factsOnly)}',
    );
    final reservedPromptTokens = summarizePromptReserveTokens(
      userInstructions: instructions,
      constraints: constraints,
      factsOnly: factsOnly,
    );
    final chunkTokenBudget = _chunkEngine.chunkTokenBudget(
      reservedPromptTokens: reservedPromptTokens,
    );
    final experimentBudget = SummarizeChunkExperiment.resolveBudget(
      chunkTokenBudget: chunkTokenBudget,
      overlapTokens: _chunkEngine.overlapTokens,
    );
    final plan = planInputChunks(
      inputText,
      reservedPromptTokens: reservedPromptTokens,
      experimentalSourceChunkTokenCap: experimentBudget.active
          ? experimentBudget.requestedSourceChunkTokens
          : null,
    );
    if (experimentBudget.active) {
      _log(SummarizeChunkExperiment.activationLogLine(experimentBudget));
    }
    _log(
      '[CHUNK PLAN] inputChars=${inputText.length} '
      'chunks=${plan.totalChunks} '
      'finalKeyPointCount=$keyPointCount '
      'mapEvidenceTarget=$_mapIntermediateEvidenceTarget '
      'reservedPromptTokens=$reservedPromptTokens '
      'chunkBudgetTokens=${plan.tokenBudgetPerChunk} '
      'overlapTokens=${plan.overlapTokens} '
      'safeTotalBodyTokens=${plan.safeTotalSourceBodyTokenBudget ?? experimentBudget.safeTotalSourceBodyTokenBudget} '
      'effectiveTotalBodyTokens=${plan.effectiveTotalSourceBodyTokenBudget ?? experimentBudget.effectiveTotalSourceBodyTokenBudget} '
      'preOverlapPackTokens=${plan.preOverlapPackTokenBudget ?? experimentBudget.preOverlapPackTokenBudget}',
    );
    for (final chunk in plan.chunks) {
      _log(
        '[CHUNK PLAN DETAIL] index=${chunk.chunkIndex + 1}/${plan.totalChunks} '
        'range=${chunk.processedRange.startChar}-${chunk.processedRange.endChar} '
        'sourceChars=${chunk.text.length} '
        'estimatedTokens=${chunk.estimatedTokens} '
        'overlapChars=${chunk.overlapChars}',
      );
    }
    if (plan.totalChunks > 1) {
      _logMapPromptFit(
        inputText: inputText,
        plan: plan,
        userInstructions: instructions,
        constraints: constraints,
        factsOnly: factsOnly,
      );
    }
    final correctiveBudget = CorrectiveInferenceBudget();
    if (SummarizeEvidencePipeline.enabled) {
      _log(SummarizeEvidencePipeline.activationLogMarker);
    }
    final stageCalls = <SummarizeInferenceStage, int>{};
    final checkpointScope =
        assignmentId != null && fenceToken != null && _checkpointManager != null
        ? SummarizeCheckpointScope(
            assignmentId: assignmentId,
            fenceToken: fenceToken,
            checkpointManager: _checkpointManager,
            onChunkSaved: onChunkCheckpoint,
          )
        : null;
    final pipeline = HierarchicalSummarizePipeline(
      contextBudget: _contextBudget,
      log: log,
      mode: mode,
      runPromptJson: (prompt, {required inferenceStage}) async {
        stageCalls[inferenceStage] = (stageCalls[inferenceStage] ?? 0) + 1;
        final correctiveBefore = correctiveBudget.used;
        final result = await runJsonTask(
          prompt: prompt,
          inferenceStage: inferenceStage,
          outputSchema: _outputSchemaForStage(
            inferenceStage,
            outputSchema: outputSchema,
          ),
          signingKey: signingKey,
          maxArrayItems: keyPointCount,
          labeledFallback: true,
          correctiveBudget: correctiveBudget,
        );
        final facts = result['facts'];
        _log(
          '[SUMMARIZE STAGE DONE] stage=${inferenceStage.name} '
          'mode=${mode.logLabel} normalCall=1 '
          'correctiveCalls=${correctiveBudget.used - correctiveBefore} '
          'correctiveRemaining=${correctiveBudget.maxCalls - correctiveBudget.used}'
          '${facts is List ? ' acceptedFacts=${facts.length}' : ''}',
        );
        return result;
      },
    );
    var rawResult = await pipeline.summarize(
      inputText: inputText,
      plan: plan,
      userInstructions: instructions,
      constraints: constraints,
      checkpointScope: checkpointScope,
      shouldContinue: () => isCancelled?.call() != true,
    );
    _log('[SUMMARY RAW RESPONSE] response=${jsonEncode(rawResult)}');
    var normalized = SummarizeOutputNormalizer.normalize(rawResult);
    var result = Map<String, dynamic>.from(normalized.normalized);
    var validation = SummarizeOutputValidator.validate(
      summary: result,
      constraints: constraints,
    );
    _logValidation(validation, prefix: 'STRUCTURAL');
    if (!validation.passed && correctiveBudget.consume()) {
      final factsEvidence = factsOnly ? pipeline.lastFinalReduceEvidenceJson : null;
      final repairPrompt = factsEvidence != null
          ? _factsOnlySummaryRepairPrompt(
              evidenceJson: factsEvidence,
              invalidSummaryJson: jsonEncode(result),
              validationIssue: validation.blockingViolations.join('; '),
              userInstructions: instructions,
              constraints: constraints,
            )
          : _summaryRepairPrompt(
              sourceText: inputText,
              invalidSummaryJson: jsonEncode(result),
              validationIssue: validation.blockingViolations.join('; '),
              userInstructions: instructions,
              constraints: constraints,
            );
      _log(
        '[SUMMARY CONSTRAINT REPAIR INPUT] '
        'source=${factsEvidence != null ? "factsOnlyFinalEvidence" : "sourceText"} '
        'correctiveRemaining=${correctiveBudget.maxCalls - correctiveBudget.used}',
      );
      if (repairPrompt == null) {
        _log(
          '[SUMMARY CONSTRAINT REPAIR SKIPPED] '
          'reason=${validation.blockingViolations.join("; ")}',
        );
      } else {
        _log(
          '[SUMMARY CONSTRAINT REPAIR] '
          'reason=${validation.blockingViolations.join("; ")}',
        );
        stageCalls[SummarizeInferenceStage.constraintRepair] =
            (stageCalls[SummarizeInferenceStage.constraintRepair] ?? 0) + 1;
        rawResult = await runJsonTask(
          prompt: repairPrompt,
          inferenceStage: SummarizeInferenceStage.constraintRepair,
          outputSchema: outputSchema ?? _summaryOutputSchema,
          signingKey: signingKey,
          maxArrayItems: keyPointCount,
          labeledFallback: true,
          correctiveBudget: correctiveBudget,
        );
        _log('[SUMMARY REPAIR RAW RESPONSE] response=${jsonEncode(rawResult)}');
        normalized = SummarizeOutputNormalizer.normalize(rawResult);
        result = Map<String, dynamic>.from(normalized.normalized);
        validation = SummarizeOutputValidator.validate(
          summary: result,
          constraints: constraints,
        );
        _logValidation(validation, prefix: 'CONSTRAINT');
      }
    }
    _log(
      '[SUMMARIZE TASK CALLS] taskId=${taskId ?? "unknown"} mode=${mode.logLabel} '
      'directPublic=${stageCalls[SummarizeInferenceStage.directPublic] ?? 0} '
      'map=${stageCalls[SummarizeInferenceStage.mapEvidence] ?? 0} '
      'intermediate=${stageCalls[SummarizeInferenceStage.intermediateEvidence] ?? 0} '
      'final=${stageCalls[SummarizeInferenceStage.finalPublic] ?? 0} '
      'constraintRepair=${stageCalls[SummarizeInferenceStage.constraintRepair] ?? 0} '
      'correctiveTotal=${correctiveBudget.used} '
      'structuralValidation=${validation.passed ? "passed" : "failed"}',
    );
    if (!validation.passed) {
      throw WorkerError(
        code: WorkerErrorCode.outputSchemaMismatch,
        message:
            'Summary constraint validation failed: '
            '${validation.blockingViolations.join("; ")}',
        retryable: false,
        stage: WorkerTaskStage.llm,
      );
    }
    _log('[SUMMARY VALIDATION OK] response=${jsonEncode(result)}');
    WorkerContentDiagnostics.logText(
      label: 'SUMMARY NORMALIZED RESULT',
      content: jsonEncode(result),
    );
    return result;
  }

  /// Isolated Map evidence diagnostic — not a public summarize task result.
  ///
  /// Uses production [PromptTemplates.summarizeMapChunk] → [runJsonTask] with
  /// [SummarizeInferenceStage.mapEvidence]. Does not run Reduce or upload output.
  Future<SummarizeMapEvidenceDiagnosticResult> runIsolatedMapEvidenceDiagnostic({
    required String signingKey,
    String? runId,
    SummarizeMapEvidenceDiagnosticFixtureId fixtureId =
        SummarizeMapEvidenceDiagnosticFixtureId.baselineFactLines,
    String? sourceText,
    String? userInstructions,
    SummarizeTaskConstraintsV1? constraints,
    SummarizeMapPromptVariant? promptVariant,
  }) async {
    SummarizeDiagnosticMap.assertArmedOrThrow();
    SummarizeChunkExperiment.assertValidConfigurationOrThrow();
    final resolvedVariant =
        promptVariant ?? SummarizeDiagnosticMap.promptVariant;

    final resolvedRunId = runId ?? SummarizeDiagnosticMap.newRunId();
    final inputText =
        sourceText ?? sourceForMapEvidenceDiagnosticFixture(fixtureId);
    final instructions = resolveSummarizeInstructions(
      userInstructions ?? summarizeMapEvidenceDiagnosticInstructions,
    );
    final resolvedConstraints =
        constraints ?? summarizeMapEvidenceDiagnosticConstraints();

    _assertInstructionsFitOrThrow(
      instructions: instructions,
      constraints: resolvedConstraints,
    );
    _assertMapPromptFitsOrThrow(
      instructions: instructions,
      constraints: resolvedConstraints,
    );

    final normalized = inputText.replaceAll('\r\n', '\n');
    final sourceSha256 = sha256HexString(normalized);
    final sourceChars = normalized.length;

    final reservedPromptTokens = summarizePromptReserveTokens(
      userInstructions: instructions,
      constraints: resolvedConstraints,
    );
    final experimentBudget = SummarizeChunkExperiment.resolveBudget(
      chunkTokenBudget: _chunkEngine.chunkTokenBudget(
        reservedPromptTokens: reservedPromptTokens,
      ),
      overlapTokens: _chunkEngine.overlapTokens,
    );
    final plan = planInputChunks(
      normalized,
      reservedPromptTokens: reservedPromptTokens,
      experimentalSourceChunkTokenCap: experimentBudget.active
          ? experimentBudget.requestedSourceChunkTokens
          : null,
    );
    _assertDiagnosticMapBodyCoversFullSource(
      normalized: normalized,
      plan: plan,
      fixtureId: fixtureId,
    );
    final chunk = plan.chunks.single;
    const stage = SummarizeInferenceStage.mapEvidence;
    const stageLabel = 'mapEvidence';
    final prompt = PromptTemplates.summarizeMapChunkEvidenceDiagnostic(
      chunkText: chunk.text,
      chunkIndex: chunk.chunkIndex,
      totalChunks: plan.totalChunks,
      chunkId: chunk.chunkId,
      userInstructions: instructions,
      constraints: resolvedConstraints,
      promptVariant: resolvedVariant,
    );
    if (!_fitsDirectInference(prompt)) {
      throw WorkerError(
        code: WorkerErrorCode.invalidTask,
        message:
            'Diagnostic Map prompt (variant=${resolvedVariant.logLabel}) '
            'exceeds the map-stage inference budget',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
    }
    final promptSha256 = sha256HexString(prompt);

    _log(
      '[SUMMARIZE MAP EVIDENCE DIAGNOSTIC] runId=$resolvedRunId '
      'fixture=${fixtureId.logLabel} '
      'variant=${resolvedVariant.logLabel} promptSha256=$promptSha256 '
      'sourceChars=$sourceChars sourceSha256=$sourceSha256 '
      'stage=$stageLabel chunks=${plan.totalChunks} '
      'chunkRange=${chunk.processedRange.startChar}-${chunk.processedRange.endChar} '
      'mapBodyChars=${chunk.text.length} fullSourceInMapBody=${chunk.text == normalized}',
    );

    final correctiveBudget = CorrectiveInferenceBudget();
    const normalInferenceCalls = 1;
    var stopReason = 'unknown';
    var truncated = false;
    var rawResponse = '';
    Map<String, dynamic>? validatedEvidence;
    WorkerError? failure;
    final inferenceStopwatch = Stopwatch()..start();
    final policy = SummarizeStagePolicy.forStage(stage);

    try {
      await ensureLoaded(signingKey: signingKey);
      WorkerContentDiagnostics.logInferencePrompt(
        stage: stageLabel,
        chunkIndex: chunk.chunkIndex,
        totalChunks: plan.totalChunks,
        prompt: prompt,
      );
      _log(
        '[MODEL REQUEST] stage=$stageLabel promptChars=${prompt.length} '
        'prompt="${_preview(prompt)}"',
      );
      final reply = await _runPromptReply(prompt, signingKey: signingKey);
      rawResponse = reply.text;
      stopReason = reply.stopReason;
      truncated = reply.truncated;
      WorkerContentDiagnostics.logInferenceResponse(
        stage: stageLabel,
        raw: rawResponse,
        stopReason: stopReason,
        truncated: truncated,
      );
      _log(
        '[MODEL RESPONSE] stage=$stageLabel responseChars=${rawResponse.length} '
        'truncated=$truncated stopReason=$stopReason '
        'response="${_preview(rawResponse)}"',
      );
      validatedEvidence = await _parseJsonResponse(
        raw: rawResponse,
        signingKey: signingKey,
        truncated: truncated,
        stopReason: stopReason,
        inferenceStage: stage,
        policy: policy,
        correctiveBudget: correctiveBudget,
      );
      _assertUsableMapPartial(
        partial: validatedEvidence,
        generationTruncated: truncated,
        stopReason: stopReason,
        policy: policy,
      );
      if (resolvedVariant == SummarizeMapPromptVariant.factsOnly) {
        _assertFactsOnlyExtraction(validatedEvidence);
      }
    } on WorkerError catch (error) {
      failure = error;
      _log(
        '[SUMMARIZE MAP EVIDENCE DIAGNOSTIC FAILED] runId=$resolvedRunId '
        'code=${error.code} message=${error.message}',
      );
    } finally {
      inferenceStopwatch.stop();
    }

    final correctiveCalls = correctiveBudget.used;
    final firstPassSuccess =
        failure == null && !truncated && correctiveCalls == 0;
    final repairedSuccess = failure == null && correctiveCalls > 0;

    String? experimentId;
    FactsOnlyExtractionSnapshot? factsSnapshot;
    if (resolvedVariant == SummarizeMapPromptVariant.factsOnly) {
      experimentId = 'diag_exp_${resolvedRunId.replaceFirst('diag_map_', '')}';
      if (failure == null && !truncated && validatedEvidence != null) {
        factsSnapshot = FactsOnlyExtractionSnapshot(
          experimentId: experimentId,
          extractionRunId: resolvedRunId,
          fixtureId: fixtureId,
          facts: (validatedEvidence['facts'] as List).cast<String>(),
          correctiveBudget: correctiveBudget,
        );
      }
      _log(
        '[FACTS ONLY EXTRACTION] experimentId=$experimentId '
        'extractionRunId=$resolvedRunId fixture=${fixtureId.logLabel} '
        'classificationEnabled=${factsSnapshot != null} '
        'factCount=${factsSnapshot?.facts.length ?? 0} '
        'factsSha256=${factsSnapshot?.factsSha256 ?? "none"}',
      );
    }

    _log(
      '[SUMMARIZE MAP EVIDENCE DIAGNOSTIC REPORT] runId=$resolvedRunId '
      'experimentId=${experimentId ?? "none"} '
      'fixture=${fixtureId.logLabel} '
      'variant=${resolvedVariant.logLabel} promptSha256=$promptSha256 '
      'sourceChars=$sourceChars sourceSha256=$sourceSha256 '
      'fullSourceInMapBody=${chunk.text == normalized} '
      'stage=$stageLabel promptChars=${prompt.length} '
      'rawResponseChars=${rawResponse.length} stopReason=$stopReason '
      'truncated=$truncated normalInferenceCalls=$normalInferenceCalls '
      'correctiveInferenceCalls=$correctiveCalls '
      'inferenceMs=${inferenceStopwatch.elapsedMilliseconds} '
      'firstPassSuccess=$firstPassSuccess repairedSuccess=$repairedSuccess '
      'failure=${failure?.message ?? "none"} '
      'validatedEvidence=${validatedEvidence == null ? "null" : _preview(jsonEncode(validatedEvidence))}',
    );
    if (validatedEvidence != null) {
      WorkerContentDiagnostics.logText(
        label: 'DIAGNOSTIC MAP EVIDENCE VALIDATED',
        content: jsonEncode(validatedEvidence),
        metadata: {
          'runId': resolvedRunId,
          'stage': stageLabel,
          'fixture': fixtureId.logLabel,
          'variant': resolvedVariant.logLabel,
        },
      );
    }

    return SummarizeMapEvidenceDiagnosticResult(
      runId: resolvedRunId,
      experimentId: experimentId,
      factsSnapshot: factsSnapshot,
      fixtureId: fixtureId,
      promptVariant: resolvedVariant,
      promptSha256: promptSha256,
      sourceChars: sourceChars,
      sourceSha256: sourceSha256,
      inferenceStage: stageLabel,
      promptChars: prompt.length,
      rawResponseChars: rawResponse.length,
      stopReason: stopReason,
      truncated: truncated,
      normalInferenceCalls: normalInferenceCalls,
      correctiveInferenceCalls: correctiveCalls,
      inferenceMs: inferenceStopwatch.elapsedMilliseconds,
      firstPassSuccess: firstPassSuccess,
      validatedEvidence: validatedEvidence,
      failure: failure,
    );
  }

  /// Rejects, never rewrites, a facts-only extraction that classified anyway.
  void _assertFactsOnlyExtraction(Map<String, dynamic> evidence) {
    final openItems = evidence['openItems'] as List;
    final priority = evidence['priority'] as String;
    final facts = evidence['facts'] as List;
    final String? issue;
    if (facts.isEmpty) {
      issue = 'facts_only_facts_empty';
    } else if (openItems.isNotEmpty || priority.trim().isNotEmpty) {
      issue = 'facts_only_classification_fields_populated:'
          'openItems=${openItems.length}:priorityChars=${priority.length}';
    } else {
      issue = null;
    }
    if (issue == null) {
      return;
    }
    _log('[FACTS ONLY EXTRACTION REJECTED] reason=$issue');
    throw WorkerError(
      code: WorkerErrorCode.outputSchemaMismatch,
      message: 'Facts-only extraction rejected ($issue)',
      retryable: false,
      stage: WorkerTaskStage.llm,
    );
  }

  /// Facts-only experiment Step 2. Sees only [snapshot].facts, never the source,
  /// and spends the experiment's shared corrective allowance.
  Future<FactsClassificationDiagnosticResult> runFactsOnlyClassificationDiagnostic({
    required String signingKey,
    required FactsOnlyExtractionSnapshot snapshot,
  }) async {
    SummarizeDiagnosticMap.assertArmedOrThrow();
    snapshot.markClassificationStarted();

    final classificationRunId = SummarizeDiagnosticMap.newRunId()
        .replaceFirst('diag_map_', 'diag_cls_');
    final facts = snapshot.facts;
    final prompt = PromptTemplates.factsClassificationDiagnostic(facts: facts);
    if (!_fitsDirectInference(prompt)) {
      throw WorkerError(
        code: WorkerErrorCode.invalidTask,
        message: 'Facts classification prompt exceeds the inference budget',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
    }
    final promptSha256 = sha256HexString(prompt);
    final budget = snapshot.correctiveBudget;
    final correctiveBefore = budget.used;
    const stageLabel = 'factsClassification';

    _log(
      '[FACTS CLASSIFICATION DIAGNOSTIC] experimentId=${snapshot.experimentId} '
      'extractionRunId=${snapshot.extractionRunId} '
      'classificationRunId=$classificationRunId '
      'fixture=${snapshot.fixtureId.logLabel} factCount=${facts.length} '
      'factsSha256=${snapshot.factsSha256} promptSha256=$promptSha256 '
      'correctiveBudgetRemaining=${budget.maxCalls - budget.used}',
    );

    var stopReason = 'unknown';
    var truncated = false;
    var rawResponse = '';
    Map<String, dynamic>? validated;
    WorkerError? failure;
    final stopwatch = Stopwatch()..start();
    try {
      WorkerContentDiagnostics.logInferencePrompt(
        stage: stageLabel,
        chunkIndex: 0,
        totalChunks: 1,
        prompt: prompt,
      );
      final reply = await _runPromptReply(prompt, signingKey: signingKey);
      rawResponse = reply.text;
      stopReason = reply.stopReason;
      truncated = reply.truncated;
      WorkerContentDiagnostics.logInferenceResponse(
        stage: stageLabel,
        raw: rawResponse,
        stopReason: stopReason,
        truncated: truncated,
      );
      _log(
        '[MODEL RESPONSE] stage=$stageLabel call=normal '
        'responseChars=${rawResponse.length} truncated=$truncated '
        'stopReason=$stopReason response="${_preview(rawResponse)}"',
      );
      validated = await _parseFactsClassification(
        raw: rawResponse,
        truncated: truncated,
        stopReason: stopReason,
        factCount: facts.length,
        signingKey: signingKey,
        budget: budget,
      );
    } on WorkerError catch (error) {
      failure = error;
      _log(
        '[FACTS CLASSIFICATION DIAGNOSTIC FAILED] '
        'classificationRunId=$classificationRunId '
        'code=${error.code} message=${error.message}',
      );
    } finally {
      stopwatch.stop();
    }

    final result = FactsClassificationDiagnosticResult(
      experimentId: snapshot.experimentId,
      extractionRunId: snapshot.extractionRunId,
      classificationRunId: classificationRunId,
      fixtureId: snapshot.fixtureId,
      factsSha256: snapshot.factsSha256,
      factCount: facts.length,
      promptSha256: promptSha256,
      rawResponseChars: rawResponse.length,
      stopReason: stopReason,
      truncated: truncated,
      correctiveCallsThisStep: budget.used - correctiveBefore,
      correctiveCallsExperimentTotal: budget.used,
      inferenceMs: stopwatch.elapsedMilliseconds,
      validatedClassification: validated,
      failure: failure,
    );
    _log(
      '[FACTS CLASSIFICATION DIAGNOSTIC REPORT] '
      'experimentId=${result.experimentId} '
      'extractionRunId=${result.extractionRunId} '
      'classificationRunId=${result.classificationRunId} '
      'fixture=${result.fixtureId.logLabel} factsSha256=${result.factsSha256} '
      'promptSha256=${result.promptSha256} '
      'rawResponseChars=${result.rawResponseChars} stopReason=$stopReason '
      'truncated=$truncated normalInferenceCalls=${result.normalInferenceCalls} '
      'correctiveCallsThisStep=${result.correctiveCallsThisStep} '
      'correctiveCallsExperimentTotal=${result.correctiveCallsExperimentTotal} '
      'inferenceMs=${result.inferenceMs} '
      'firstPassSuccess=${result.firstPassSuccess} '
      'repairedSuccess=${result.repairedSuccess} '
      'semanticSupportCheck=${result.semanticSupportCheck} '
      'failure=${failure?.message ?? "none"} '
      'classification=${validated == null ? "null" : jsonEncode(validated)}',
    );
    return result;
  }

  Future<Map<String, dynamic>> _parseFactsClassification({
    required String raw,
    required bool truncated,
    required String stopReason,
    required int factCount,
    required String signingKey,
    required CorrectiveInferenceBudget budget,
  }) async {
    if (truncated) {
      throw WorkerError(
        code: WorkerErrorCode.outputSchemaMismatch,
        message:
            'Facts classification truncated (stopReason=$stopReason); no repair',
        retryable: false,
        stage: WorkerTaskStage.llm,
      );
    }
    var parsed = JsonOutputValidator.extractJsonObject(
      raw,
      allowSalvage: false,
    ).object;
    if (parsed == null) {
      if (!budget.consume()) {
        _log('[JSON REPAIR SKIPPED] stage=factsClassification '
            'corrective budget exhausted');
      } else {
        _log('[JSON CORRECTIVE] action=json_repair stage=factsClassification '
            'call=corrective budgetRemaining=${budget.maxCalls - budget.used}');
        final repairPrompt = _jsonRepairPrompt(raw);
        if (repairPrompt != null) {
          final repair = await _runPromptReply(
            repairPrompt,
            signingKey: signingKey,
          );
          _log(
            '[MODEL RESPONSE] stage=factsClassification call=corrective '
            'responseChars=${repair.text.length} truncated=${repair.truncated} '
            'stopReason=${repair.stopReason}',
          );
          if (!repair.truncated) {
            parsed = JsonOutputValidator.extractJsonObject(
              repair.text,
              allowSalvage: false,
            ).object;
          }
        }
      }
    }
    if (parsed == null) {
      throw WorkerError(
        code: WorkerErrorCode.llmInvalidJson,
        message: 'Facts classification is not valid JSON',
        retryable: false,
        stage: WorkerTaskStage.llm,
      );
    }
    final issue = FactsClassificationSchema.validate(
      parsed,
      factCount: factCount,
    );
    if (issue != null) {
      throw WorkerError(
        code: WorkerErrorCode.outputSchemaMismatch,
        message: 'Facts classification rejected ($issue)',
        retryable: false,
        stage: WorkerTaskStage.llm,
      );
    }
    return parsed;
  }

  void _assertDiagnosticMapBodyCoversFullSource({
    required String normalized,
    required ChunkPlan plan,
    required SummarizeMapEvidenceDiagnosticFixtureId fixtureId,
  }) {
    if (plan.totalChunks > 1) {
      throw WorkerError(
        code: WorkerErrorCode.invalidTask,
        message:
            'Diagnostic mapEvidence requires one Map body with the full fixture '
            '(fixture=${fixtureId.logLabel}); chunk plan has ${plan.totalChunks} '
            'chunks. Disable SUMMARIZE_EXPERIMENT_SOURCE_CHUNK_TOKENS for '
            'diagnostic runs.',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
    }
    final chunk = plan.chunks.single;
    if (chunk.text != normalized) {
      throw WorkerError(
        code: WorkerErrorCode.invalidTask,
        message:
            'Diagnostic fixture is not fully present in the Map chunk body '
            '(fixture=${fixtureId.logLabel} sourceChars=${normalized.length} '
            'mapBodyChars=${chunk.text.length} '
            'processedRange=${chunk.processedRange.startChar}-'
            '${chunk.processedRange.endChar})',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
    }
  }

  void _logValidation(SummarizeValidationResult validation, {required String prefix}) {
    if (validation.passed) {
      _log('[SUMMARY $prefix OK]');
    } else {
      _log(
        '[SUMMARY $prefix FAILED] '
        'violations=${validation.blockingViolations.join("; ")}',
      );
    }
    if (validation.uncheckedCoverageAxes.isNotEmpty) {
      _log(
        '[SUMMARY UNCHECKED AXES] '
        'axes=${validation.uncheckedCoverageAxes.join(", ")}',
      );
    }
    if (validation.uncheckedBillingRuleIds.isNotEmpty) {
      _log(
        '[SUMMARY UNCHECKED BILLING RULES] '
        'rules=${validation.uncheckedBillingRuleIds.join(", ")}',
      );
    }
  }

  void _logMapPromptFit({
    required String inputText,
    required ChunkPlan plan,
    required String? userInstructions,
    SummarizeTaskConstraintsV1? constraints,
    bool factsOnly = false,
  }) {
    final chunk = plan.chunks.first;
    final prompt = PromptTemplates.summarizeMapChunk(
      chunkText: chunk.text,
      chunkIndex: chunk.chunkIndex,
      totalChunks: plan.totalChunks,
      chunkId: chunk.chunkId,
      userInstructions: userInstructions,
      constraints: constraints,
      evidenceTarget: _mapIntermediateEvidenceTarget,
      factsOnly: factsOnly,
    );
    final evaluation = _contextBudget.evaluateFormattedPrompt(
      formattedPrompt: FormattedPromptBuilder.buildTaskPrompt(
        templateBody: prompt,
        systemInstruction: _contextBudget.defaultSystemInstruction,
      ),
      maxOutputTokens: config.maxOutputTokens,
    );
    _log(
      '[CHUNK MAP PROMPT FIT] index=${chunk.chunkIndex + 1}/${plan.totalChunks} '
      'fitsDirectInference=${evaluation.fitsDirectInference} '
      'estimatedPromptTokens=${evaluation.formattedPromptTokens} '
      'inputBudgetTokens=${_contextBudget.profile.inputBudgetTokens} '
      'maxOutputTokens=${evaluation.maxOutputTokens}',
    );
  }

  Map<String, dynamic>? _outputSchemaForStage(
    SummarizeInferenceStage stage, {
    Map<String, dynamic>? outputSchema,
  }) {
    final policy = SummarizeStagePolicy.forStage(stage);
    if (policy.usesEvidenceSchema) {
      return null;
    }
    return outputSchema ?? _summaryOutputSchema;
  }

  bool labeledFallbackEnabled({
    required String? sourcePrompt,
    required SummarizeStagePolicy policy,
  }) =>
      sourcePrompt != null && policy.allowLabeledFallback;

  void _logJsonRejection({
    required JsonExtractResult extract,
    required SummarizeStagePolicy policy,
    required String stopReason,
    required bool truncated,
    CorrectiveInferenceBudget? correctiveBudget,
  }) {
    _log(
      '[JSON EXTRACT REJECTED] stage=${policy.logLabel} '
      'reason=${extract.rejectionReason ?? "unknown"} '
      'extractStage=${extract.rejectionStage ?? "unknown"} '
      'stopReason=$stopReason truncated=$truncated '
      'correctiveRemaining=${correctiveBudget == null ? "unbounded" : correctiveBudget.hasRemaining ? correctiveBudget.maxCalls - correctiveBudget.used : 0}',
    );
  }

  void _logCorrectiveAttempt({
    required String action,
    required SummarizeStagePolicy policy,
    required String stopReason,
    required bool truncated,
    CorrectiveInferenceBudget? correctiveBudget,
    String? rejectionReason,
  }) {
    _log(
      '[JSON CORRECTIVE] action=$action stage=${policy.logLabel} '
      'priorReason=${rejectionReason ?? "unknown"} '
      'stopReason=$stopReason truncated=$truncated '
      'budgetRemaining=${correctiveBudget == null ? "unbounded" : correctiveBudget.maxCalls - correctiveBudget.used}',
    );
  }

  void _assertInstructionsFitOrThrow({
    required String? instructions,
    SummarizeTaskConstraintsV1? constraints,
  }) {
    if (instructions == null) {
      return;
    }
    final prompt = PromptTemplates.textSummarize(
      sourceText: '',
      userInstructions: instructions,
      constraints: constraints,
    );
    if (!_fitsDirectInference(prompt)) {
      throw WorkerError(
        code: WorkerErrorCode.invalidTask,
        message:
            'Customer instructions exceed the direct inference budget; '
            'shorten structured options or instructions',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
    }
  }

  void _assertMapPromptFitsOrThrow({
    required String? instructions,
    SummarizeTaskConstraintsV1? constraints,
    bool factsOnly = false,
  }) {
    final prompt = PromptTemplates.summarizeMapChunk(
      chunkText: '',
      chunkIndex: 0,
      totalChunks: 999,
      chunkId: '0' * 64,
      userInstructions: instructions,
      constraints: constraints,
      evidenceTarget: _mapIntermediateEvidenceTarget,
      factsOnly: factsOnly,
    );
    if (!_fitsDirectInference(prompt)) {
      throw WorkerError(
        code: WorkerErrorCode.invalidTask,
        message:
            'Customer instructions exceed the map-stage inference budget; '
            'shorten structured options or instructions',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
    }
  }

  String? _summaryRepairPrompt({
    required String sourceText,
    required String invalidSummaryJson,
    required String validationIssue,
    required String? userInstructions,
    SummarizeTaskConstraintsV1? constraints,
  }) {
    var excerpt = sourceText;
    while (true) {
      final prompt = PromptTemplates.summaryConstraintRepair(
        sourceText: excerpt,
        invalidSummaryJson: invalidSummaryJson,
        validationIssue: validationIssue,
        userInstructions: userInstructions,
        constraints: constraints,
      );
      if (_fitsDirectInference(prompt)) {
        return prompt;
      }
      if (excerpt.length <= _minRepairExcerptChars) {
        return null;
      }
      excerpt = excerpt.substring(0, excerpt.length ~/ 2);
    }
  }

  /// Never shortens the evidence; returns null when the full prompt does not fit.
  String? _factsOnlySummaryRepairPrompt({
    required String evidenceJson,
    required String invalidSummaryJson,
    required String validationIssue,
    required String? userInstructions,
    SummarizeTaskConstraintsV1? constraints,
  }) {
    final prompt = PromptTemplates.summaryConstraintRepairFromFactsEvidence(
      evidenceJson: evidenceJson,
      invalidSummaryJson: invalidSummaryJson,
      validationIssue: validationIssue,
      userInstructions: userInstructions,
      constraints: constraints,
    );
    if (_fitsDirectInference(prompt)) {
      return prompt;
    }
    _log('[SUMMARY CONSTRAINT REPAIR] factsOnly prompt does not fit; not shortened');
    return null;
  }

  bool _fitsDirectInference(String prompt) => _contextBudget
      .evaluateFormattedPrompt(
        formattedPrompt: FormattedPromptBuilder.buildTaskPrompt(
          templateBody: prompt,
          systemInstruction: _contextBudget.defaultSystemInstruction,
        ),
        maxOutputTokens: config.maxOutputTokens,
      )
      .fitsDirectInference;

  /// Tokens consumed by everything wrapped around the chunk body, measured on
  /// the widest summarize template so a planned chunk can never overflow the
  /// direct-inference budget once its prompt is built.
  int summarizePromptReserveTokens({
    String? userInstructions,
    SummarizeTaskConstraintsV1? constraints,
    bool factsOnly = false,
  }) {
    final estimator = _contextBudget.estimator;
    final system = _contextBudget.defaultSystemInstruction;
    final direct = FormattedPromptBuilder.buildTaskPrompt(
      templateBody: PromptTemplates.textSummarize(
        sourceText: '',
        userInstructions: userInstructions,
        constraints: constraints,
      ),
      systemInstruction: system,
    );
    final mapped = FormattedPromptBuilder.buildTaskPrompt(
      templateBody: PromptTemplates.summarizeMapChunk(
        chunkText: '',
        chunkIndex: 0,
        totalChunks: 999,
        chunkId: '0' * 64,
        userInstructions: userInstructions,
        constraints: constraints,
        evidenceTarget: _mapIntermediateEvidenceTarget,
        factsOnly: factsOnly,
      ),
      systemInstruction: system,
    );
    final directTokens = estimator.estimate(direct);
    final mappedTokens = estimator.estimate(mapped);
    return directTokens > mappedTokens ? directTokens : mappedTokens;
  }

  void _assertUsableMapPartial({
    required Map<String, dynamic> partial,
    required bool generationTruncated,
    required SummarizeStagePolicy policy,
    String? stopReason,
  }) {
    if (policy.usesEvidenceSchema) {
      _assertUsableEvidencePartial(
        partial: partial,
        generationTruncated: generationTruncated,
        stopReason: stopReason,
        stageLabel: policy.logLabel,
      );
      return;
    }
    final issues = MapPartialValidator.validate(
      partial: partial,
      generationTruncated: generationTruncated,
      stopReason: stopReason,
    );
    if (issues.isEmpty) {
      return;
    }
    _log('[MAP PARTIAL REJECTED] issues=${issues.join('; ')}');
    throw WorkerError(
      code: WorkerErrorCode.outputSchemaMismatch,
      message: 'Map chunk partial is incomplete: ${issues.join('; ')}',
      retryable: false,
      stage: WorkerTaskStage.llm,
    );
  }

  void _assertUsableEvidencePartial({
    required Map<String, dynamic> partial,
    required bool generationTruncated,
    required String stageLabel,
    String? stopReason,
  }) {
    final issues = EvidencePartialValidator.validate(
      partial: partial,
      generationTruncated: generationTruncated,
      stopReason: stopReason,
    );
    if (issues.isEmpty) {
      return;
    }
    _log('[EVIDENCE PARTIAL REJECTED] stage=$stageLabel issues=${issues.join('; ')}');
    throw WorkerError(
      code: WorkerErrorCode.outputSchemaMismatch,
      message:
          'Evidence partial is invalid at $stageLabel: ${issues.join('; ')}',
      retryable: false,
      stage: WorkerTaskStage.llm,
    );
  }

  void _logEvidenceSoftTargetExceeded(Map<String, dynamic> partial) {
    final encodedLength = jsonEncode(partial).length;
    final softTarget =
        (ContextBudgetProfile.qwenBaselineOutputReserveTokens *
                const TokenEstimator().charactersPerToken *
                0.85)
            .floor();
    if (encodedLength > softTarget) {
      _log(
        '[EVIDENCE OUTPUT SOFT TARGET EXCEEDED] chars=$encodedLength '
        'softTarget=$softTarget',
      );
    }
  }

  Map<String, dynamic> _validateEvidencePartial(Map<String, dynamic> partial) {
    final structural = SummarizeEvidenceSchema.validateStructure(partial);
    if (structural != null) {
      _log('[EVIDENCE SCHEMA REJECTED] reason=$structural');
      throw WorkerError(
        code: WorkerErrorCode.outputSchemaMismatch,
        message: 'Evidence partial schema invalid ($structural)',
        retryable: false,
        stage: WorkerTaskStage.llm,
      );
    }
    return SummarizeEvidenceSchema.normalize(partial);
  }

  Map<String, dynamic>? _validateEvidencePartialOrNull(
    Map<String, dynamic> partial,
  ) {
    final structural = SummarizeEvidenceSchema.validateStructure(partial);
    if (structural != null) {
      _log('[EVIDENCE SCHEMA REJECTED] reason=$structural');
      return null;
    }
    return SummarizeEvidenceSchema.normalize(partial);
  }

  void _rejectTruncatedEvidenceGeneration({
    required SummarizeStagePolicy policy,
    required String stopReason,
    required String source,
  }) {
    _log(
      '[EVIDENCE GENERATION TRUNCATED] stage=${policy.logLabel} '
      'stopReason=$stopReason source=$source',
    );
    throw WorkerError(
      code: WorkerErrorCode.outputSchemaMismatch,
      message:
          'Evidence partial generation truncated at ${policy.logLabel} '
          '(stopReason=$stopReason; source=$source)',
      retryable: false,
      stage: WorkerTaskStage.llm,
    );
  }

  Future<Map<String, dynamic>> _parseJsonResponse({
    required String raw,
    Map<String, dynamic>? outputSchema,
    required String signingKey,
    int maxArrayItems = 3,
    bool truncated = false,
    String stopReason = 'model_eos',
    required SummarizeInferenceStage inferenceStage,
    required SummarizeStagePolicy policy,
    String? sourcePrompt,
    CorrectiveInferenceBudget? correctiveBudget,
  }) async {
    final extract = JsonOutputValidator.extractJsonObject(
      raw,
      allowSalvage: policy.allowSalvage,
    );
    var parsed = extract.object;
    if (extract.literalEscapeRecovered) {
      _log(
        '[JSON EXTRACT RECOVERED] method=literal_escape_layer '
        'stage=${policy.logLabel} chars=${raw.length}',
      );
    }
    if (parsed == null) {
      _logJsonRejection(
        extract: extract,
        policy: policy,
        stopReason: stopReason,
        truncated: truncated,
        correctiveBudget: correctiveBudget,
      );
    }
    if (policy.usesEvidenceSchema &&
        truncated &&
        policy.rejectGenerationTruncation) {
      _rejectTruncatedEvidenceGeneration(
        policy: policy,
        stopReason: stopReason,
        source: 'initial_generation',
      );
    }
    final useLabeledFallback = labeledFallbackEnabled(
      sourcePrompt: sourcePrompt,
      policy: policy,
    );
    var repairSkippedBudgetExhausted = false;
    if (parsed == null && useLabeledFallback) {
      if (correctiveBudget == null || correctiveBudget.consume()) {
        _logCorrectiveAttempt(
          action: 'labeled_fallback',
          policy: policy,
          stopReason: stopReason,
          truncated: truncated,
          correctiveBudget: correctiveBudget,
          rejectionReason: extract.rejectionReason,
        );
        parsed = await _runLabeledFallback(
          sourcePrompt: sourcePrompt!,
          signingKey: signingKey,
          keyPointCount: maxArrayItems,
          inferenceStage: inferenceStage,
        );
      } else {
        _log('[LABELED FALLBACK SKIPPED] corrective budget exhausted');
      }
    } else if (parsed == null && !useLabeledFallback) {
      if (correctiveBudget != null && !correctiveBudget.hasRemaining) {
        repairSkippedBudgetExhausted = true;
        _log('[JSON REPAIR SKIPPED] corrective budget exhausted');
      } else if (correctiveBudget == null || correctiveBudget.consume()) {
        _logCorrectiveAttempt(
          action: 'json_repair',
          policy: policy,
          stopReason: stopReason,
          truncated: truncated,
          correctiveBudget: correctiveBudget,
          rejectionReason: extract.rejectionReason,
        );
        final repairPrompt = _jsonRepairPrompt(raw);
        if (repairPrompt != null) {
          final repairReply = await _runPromptReply(
            repairPrompt,
            signingKey: signingKey,
          );
          final repairExtract = JsonOutputValidator.extractJsonObject(
            repairReply.text,
            allowSalvage: false,
          );
          parsed = repairExtract.object;
          if (repairExtract.literalEscapeRecovered) {
            _log(
              '[JSON EXTRACT RECOVERED] method=literal_escape_layer '
              'stage=${policy.logLabel} chars=${repairReply.text.length} '
              'source=json_repair',
            );
          }
          if (parsed == null) {
            _log('[JSON REPAIR FAILED] reason=repair_output_not_valid_json');
          } else if (policy.usesEvidenceSchema) {
            if (repairReply.truncated && policy.rejectGenerationTruncation) {
              _rejectTruncatedEvidenceGeneration(
                policy: policy,
                stopReason: repairReply.stopReason,
                source: 'json_repair',
              );
            }
            parsed = _validateEvidencePartialOrNull(parsed);
            if (parsed == null) {
              _log(
                '[JSON REPAIR FAILED] reason=repair_output_not_evidence_v2',
              );
            }
          }
        }
      }
    }
    if (parsed == null) {
      final reason = extract.rejectionReason ?? 'json_decode_failed';
      final evidenceStage =
          inferenceStage == SummarizeInferenceStage.mapEvidence ||
          inferenceStage == SummarizeInferenceStage.intermediateEvidence;
      final budgetExhausted = repairSkippedBudgetExhausted;
      throw WorkerError(
        code: WorkerErrorCode.llmInvalidJson,
        message: evidenceStage
            ? budgetExhausted
                ? 'Evidence partial JSON could not be recovered locally '
                    '(reason=corrective_budget_exhausted; priorReason=$reason)'
                : 'Evidence partial JSON could not be recovered locally '
                    '(reason=$reason; stopReason=$stopReason)'
            : budgetExhausted
            ? 'LLM output is not valid JSON after repair attempt '
                '(reason=corrective_budget_exhausted; priorReason=$reason)'
            : 'LLM output is not valid JSON after repair attempt '
                '(reason=$reason)',
        retryable: correctiveBudget == null,
        stage: WorkerTaskStage.llm,
      );
    }
    final summarizePath = correctiveBudget != null;
    if (policy.usesEvidenceSchema) {
      parsed = _validateEvidencePartial(parsed);
      _logEvidenceSoftTargetExceeded(parsed);
      return parsed;
    }
    if (!summarizePath) {
      parsed = JsonOutputValidator.coerceSchemaTypes(parsed, outputSchema);
    }
    if (truncated && policy.rejectGenerationTruncation) {
      throw WorkerError(
        code: WorkerErrorCode.outputSchemaMismatch,
        message:
            'Map chunk generation truncated before completion '
            '(stopReason=$stopReason)',
        retryable: false,
        stage: WorkerTaskStage.llm,
      );
    }
    if (truncated && policy.allowCompleteMissingFields) {
      final completed = JsonOutputValidator.completeMissingFields(
        parsed,
        outputSchema,
      );
      if (completed.length != parsed.length) {
        _log(
          '[OUTPUT TRUNCATED] filledFields=${completed.length - parsed.length}',
        );
      }
      parsed = completed;
    }
    var schemaError = JsonOutputValidator.validateSchema(parsed, outputSchema);
    if (schemaError != null) {
      throw schemaError;
    }

    var encoded = jsonEncode(parsed);
    var limit = _outputLimitEnforcer.evaluate(
      rawOutput: encoded,
      maxOutputTokens: _contextBudget.capMaxOutputTokens(
        config.maxOutputTokens,
      ),
      jsonRequired: true,
    );
    if (!limit.treatAsSuccess &&
        policy.allowTrimToLimits &&
        !summarizePath) {
      final shrunk = JsonOutputValidator.trimToLimits(
        parsed,
        maxArrayItems: maxArrayItems,
      );
      final shrunkEncoded = jsonEncode(shrunk);
      if (shrunkEncoded.length < encoded.length) {
        _log(
          '[JSON TRIMMED] chars=${encoded.length} '
          'trimmedChars=${shrunkEncoded.length} maxArrayItems=$maxArrayItems',
        );
        parsed = shrunk;
        encoded = shrunkEncoded;
        limit = _outputLimitEnforcer.evaluate(
          rawOutput: encoded,
          maxOutputTokens: _contextBudget.capMaxOutputTokens(
            config.maxOutputTokens,
          ),
          jsonRequired: true,
        );
      }
    }
    if (!limit.treatAsSuccess && policy.allowModelCompact) {
      if (correctiveBudget != null && !correctiveBudget.consume()) {
        _log('[MODEL COMPACT SKIPPED] corrective budget exhausted');
      } else {
        _log(
          '[MODEL COMPACT RETRY] estimatedTokens=${limit.estimatedOutputTokens} '
          'maxTokens=${limit.maxOutputTokens}',
        );
        final compactedRaw = await _runPrompt(
          PromptTemplates.jsonCompact(
            oversizedJson: encoded,
            maxOutputTokens: limit.maxOutputTokens,
            maxArrayItems: maxArrayItems,
          ),
          signingKey: signingKey,
        );
        final parsedCompact = JsonOutputValidator.parseJsonObject(compactedRaw);
        if (parsedCompact == null) {
          throw WorkerError(
            code: WorkerErrorCode.llmInvalidJson,
            message: 'Compacted LLM output is not valid JSON',
            retryable: correctiveBudget == null,
            stage: WorkerTaskStage.llm,
          );
        }
        final compacted = summarizePath
            ? parsedCompact
            : JsonOutputValidator.coerceSchemaTypes(
                parsedCompact,
                outputSchema,
              );
        schemaError = JsonOutputValidator.validateSchema(
          compacted,
          outputSchema,
        );
        if (schemaError != null) {
          throw schemaError;
        }
        _enforceOutputLimit(jsonEncode(compacted));
        _log('[MODEL COMPACT RESPONSE] response=${jsonEncode(compacted)}');
        parsed = compacted;
      }
    }
    return parsed;
  }

  /// Asks for the same content as labelled lines and rebuilds the five summary
  /// fields locally. The excerpt is shortened until the prompt fits, the same
  /// way the quality repair does.
  Future<Map<String, dynamic>?> _runLabeledFallback({
    required String sourcePrompt,
    required String signingKey,
    required int keyPointCount,
    required SummarizeInferenceStage inferenceStage,
  }) async {
    final body = PromptTemplates.delimitedBody(sourcePrompt);
    if (body == null || body.isEmpty) {
      return null;
    }
    final requestedPoints =
        inferenceStage == SummarizeInferenceStage.mapEvidence
        ? _minKeyPoints
        : keyPointCount;
    var excerpt = body;
    while (true) {
      final prompt = PromptTemplates.summarizeLabeledLines(
        sourceText: excerpt,
        keyPointCount: requestedPoints,
      );
      if (_fitsDirectInference(prompt)) {
        final raw = await _runPrompt(prompt, signingKey: signingKey);
        var parsed = LabeledSummaryParser.parse(raw);
        if (parsed != null &&
            inferenceStage == SummarizeInferenceStage.mapEvidence) {
          final issues = MapPartialValidator.validate(
            partial: parsed,
            generationTruncated: false,
          );
          if (issues.isNotEmpty) {
            _log(
              '[LABELED FALLBACK REJECTED] issues=${issues.join('; ')} '
              'requestedPoints=$requestedPoints replyChars=${raw.length}',
            );
            parsed = null;
          }
        }
        _log(
          '[LABELED FALLBACK] excerptChars=${excerpt.length} '
          'requestedPoints=$requestedPoints parsed=${parsed != null} '
          'keyPoints=${(parsed?['keyPoints'] as List?)?.length ?? 0} '
          'replyChars=${raw.length}',
        );
        return parsed;
      }
      if (excerpt.length <= _minRepairExcerptChars) {
        _log('[LABELED FALLBACK SKIPPED] bodyChars=${body.length}');
        return null;
      }
      excerpt = excerpt.substring(0, excerpt.length ~/ 2);
    }
  }

  /// Broken output can be as long as the whole context window, and a repair
  /// prompt that does not fit the budget only produces another truncated reply.
  /// Shrink the excerpt until it fits, then stop asking the model.
  String? _jsonRepairPrompt(String brokenJson) {
    var excerpt = brokenJson.trim();
    while (true) {
      final prompt = PromptTemplates.jsonRepair(brokenJson: excerpt);
      if (_fitsDirectInference(prompt)) {
        _log(
          '[JSON REPAIR] brokenChars=${brokenJson.length} '
          'excerptChars=${excerpt.length}',
        );
        return prompt;
      }
      if (excerpt.length <= _minRepairExcerptChars) {
        _log('[JSON REPAIR SKIPPED] brokenChars=${brokenJson.length}');
        return null;
      }
      excerpt = excerpt.substring(0, excerpt.length ~/ 2);
    }
  }

  Future<String> _runPrompt(
    String prompt, {
    required String signingKey,
    String? systemInstruction,
    Uint8List? imageBytes,
    int? maxOutputTokens,
  }) async {
    final reply = await _runPromptReply(
      prompt,
      signingKey: signingKey,
      systemInstruction: systemInstruction,
      imageBytes: imageBytes,
      maxOutputTokens: maxOutputTokens,
    );
    return reply.text;
  }

  /// Sends [userText] to the resident LLM with no task contract or JSON repair.
  /// When [imageBytes] is set, uses Gemma 4 multimodal input (same resident model).
  Future<String> runDirectUserText(
    String userText, {
    required String signingKey,
    Uint8List? imageBytes,
    int? maxOutputTokens,
  }) async {
    final trimmed = userText.trim();
    final hasImage = imageBytes != null && imageBytes.isNotEmpty;
    if (trimmed.isEmpty && !hasImage) {
      throw const WorkerError(
        code: WorkerErrorCode.invalidTask,
        message: 'Direct prompt text is empty',
        retryable: false,
        stage: WorkerTaskStage.llm,
      );
    }
    final prompt = trimmed.isEmpty
        ? 'Describe this image and answer any question implied by the user.'
        : trimmed;
    _log(
      '[DIRECT USER PROMPT] chars=${prompt.length} '
      'imageBytes=${imageBytes?.length ?? 0}',
    );
    return _runPrompt(
      prompt,
      signingKey: signingKey,
      systemInstruction: '',
      imageBytes: imageBytes,
      maxOutputTokens: maxOutputTokens,
    );
  }

  Future<_PromptReply> _runPromptReply(
    String prompt, {
    required String signingKey,
    String? systemInstruction,
    Uint8List? imageBytes,
    int? maxOutputTokens,
  }) async {
    final formatted = FormattedPromptBuilder.buildTaskPrompt(
      templateBody: prompt,
      systemInstruction:
          systemInstruction ?? _contextBudget.defaultSystemInstruction,
    );
    final outputCap = maxOutputTokens ?? config.maxOutputTokens;
    _contextBudget.ensureDirectInferenceOrThrow(
      prompt: prompt,
      maxOutputTokens: outputCap,
    );
    final runner = _runner;
    if (runner != null) {
      return _PromptReply(
        text: await runner(formatted),
        truncated: testRunnerTruncated,
        stopReason: testRunnerTruncated ? testRunnerStopReason : 'model_eos',
      );
    }
    await ensureLoaded(signingKey: signingKey);
    final gemmaAdapter = _adapter is GemmaLiteRtInferenceAdapter
        ? _adapter as GemmaLiteRtInferenceAdapter
        : null;
    if (gemmaAdapter != null && systemInstruction == '') {
      gemmaAdapter.usePortalPassthroughChat = true;
    }
    try {
      final InferenceOutput output;
      if (gemmaAdapter != null &&
          imageBytes != null &&
          imageBytes.isNotEmpty) {
        output = await gemmaAdapter.runUserPrompt(
          prompt: prompt,
          imageBytes: imageBytes,
          resumedState: null,
          maxOutputTokensOverride: outputCap,
        );
      } else {
        output = await _adapter.run(
          inputBytes: Uint8List.fromList(utf8.encode(prompt)),
          resumedState: null,
        );
      }
      final stopReason = output.metrics['stopReason']?.toString() ?? 'model_eos';
      return _PromptReply(
        text: utf8.decode(output.resultBytes),
        truncated: stopReason == 'output_limit' || stopReason == 'repetition',
        stopReason: stopReason,
      );
    } finally {
      gemmaAdapter?.usePortalPassthroughChat = false;
    }
  }

  String _enforceOutputLimit(String raw) {
    final evaluation = _outputLimitEnforcer.evaluate(
      rawOutput: raw,
      maxOutputTokens: _contextBudget.capMaxOutputTokens(
        config.maxOutputTokens,
      ),
      jsonRequired: true,
    );
    if (!evaluation.treatAsSuccess) {
      throw OutputLimitExceededException(evaluation);
    }
    return raw;
  }

  Future<void> dispose() async {
    if (_runner == null) {
      await _adapter.dispose();
    }
  }
}
