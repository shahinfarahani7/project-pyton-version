import 'dart:convert';
import 'dart:typed_data';

import '../../contracts/worker_error.dart';
import '../../models/worker_model_catalog.dart';
import '../../runtime/gemma_inference_adapter.dart';
import '../../runtime/inference_adapter.dart';
import '../../runtime/checkpoint_manager.dart';
import '../../runtime/model_runtime_manager.dart';
import '../../runtime/worker_content_diagnostics.dart';
import '../../validation/json_output_validator.dart';
import 'context_budget_manager.dart';
import 'formatted_prompt_builder.dart';
import 'hierarchical_reduce_bounds.dart';
import 'hierarchical_summarize_pipeline.dart';
import 'labeled_summary_parser.dart';
import 'map_partial_validator.dart';
import 'output_limit_enforcer.dart';
import 'prompt_templates.dart';
import 'semantic_chunk_engine.dart';
import 'summarize_output_normalizer.dart';
import 'summarize_output_validator.dart';
import 'summarize_task_constraints.dart';

class QwenInferenceConfig {
  const QwenInferenceConfig({
    this.contextSize = ContextBudgetProfile.qwenBaselineTotalContextTokens,
    this.maxOutputTokens = ContextBudgetProfile.qwenBaselineOutputReserveTokens,
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

  static const _minKeyPoints = 3;
  static const _minRepairExcerptChars = 400;
  static const _mapIntermediateMaxKeyPoints =
      HierarchicalReduceBounds.mapIntermediateMaxKeyPoints;

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

  ChunkPlan planInputChunks(String inputText, {int? reservedPromptTokens}) =>
      _chunkEngine.chunk(inputText, reservedPromptTokens: reservedPromptTokens);

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
    Map<String, dynamic>? outputSchema,
    required String signingKey,
    int maxArrayItems = 3,
    bool labeledFallback = false,
    CorrectiveInferenceBudget? correctiveBudget,
  }) async {
    final mapStage = prompt.contains('Chunk metadata:');
    final stage = mapStage
        ? 'map'
        : prompt.contains('Combine the partial summaries')
        ? 'reduce'
        : prompt.contains('validationIssue')
        ? 'repair'
        : 'direct';
    WorkerContentDiagnostics.logInferencePrompt(stage: stage, prompt: prompt);
    _log(
      '[MODEL REQUEST] stage=$stage promptChars=${prompt.length} '
      'prompt="${_preview(prompt)}"',
    );
    final reply = await _runPromptReply(prompt, signingKey: signingKey);
    WorkerContentDiagnostics.logInferenceResponse(
      stage: stage,
      raw: reply.text,
      stopReason: reply.stopReason,
      truncated: reply.truncated,
    );
    _log(
      '[MODEL RESPONSE] stage=$stage responseChars=${reply.text.length} '
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
      mapStage: mapStage,
      sourcePrompt: labeledFallback ? prompt : null,
      correctiveBudget: correctiveBudget,
    );
    if (mapStage) {
      _assertUsableMapPartial(
        partial: parsed,
        generationTruncated: reply.truncated,
        stopReason: reply.stopReason,
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
  }) async {
    final instructions = resolveSummarizeInstructions(userInstructions);
    final keyPointCount = constraints?.keyPointCount ?? _minKeyPoints;
    _assertInstructionsFitOrThrow(
      instructions: instructions,
      constraints: constraints,
    );
    final reservedPromptTokens = summarizePromptReserveTokens(
      userInstructions: instructions,
      constraints: constraints,
    );
    final plan = planInputChunks(
      inputText,
      reservedPromptTokens: reservedPromptTokens,
    );
    _log(
      '[CHUNK PLAN] inputChars=${inputText.length} '
      'chunks=${plan.totalChunks} keyPoints=$keyPointCount '
      'reservedPromptTokens=$reservedPromptTokens '
      'chunkBudgetTokens=${plan.tokenBudgetPerChunk}',
    );
    final correctiveBudget = CorrectiveInferenceBudget();
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
      runPromptJson: (prompt) => runJsonTask(
        prompt: prompt,
        outputSchema: outputSchema ?? _summaryOutputSchema,
        signingKey: signingKey,
        maxArrayItems: keyPointCount,
        labeledFallback: true,
        correctiveBudget: correctiveBudget,
      ),
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
      final repairPrompt = _summaryRepairPrompt(
        sourceText: inputText,
        invalidSummaryJson: jsonEncode(result),
        validationIssue: validation.blockingViolations.join('; '),
        userInstructions: instructions,
        constraints: constraints,
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
        rawResult = await runJsonTask(
          prompt: repairPrompt,
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

  bool labeledFallbackEnabled({
    required String? sourcePrompt,
    required bool mapStage,
  }) =>
      sourcePrompt != null && !mapStage;

  void _logJsonRejection({
    required JsonExtractResult extract,
    required bool mapStage,
    required String stopReason,
    required bool truncated,
    CorrectiveInferenceBudget? correctiveBudget,
  }) {
    _log(
      '[JSON EXTRACT REJECTED] stage=${mapStage ? "map" : "json"} '
      'reason=${extract.rejectionReason ?? "unknown"} '
      'extractStage=${extract.rejectionStage ?? "unknown"} '
      'stopReason=$stopReason truncated=$truncated '
      'correctiveRemaining=${correctiveBudget == null ? "unbounded" : correctiveBudget.hasRemaining ? correctiveBudget.maxCalls - correctiveBudget.used : 0}',
    );
  }

  void _logCorrectiveAttempt({
    required String action,
    required bool mapStage,
    required String stopReason,
    required bool truncated,
    CorrectiveInferenceBudget? correctiveBudget,
    String? rejectionReason,
  }) {
    _log(
      '[JSON CORRECTIVE] action=$action stage=${mapStage ? "map" : "json"} '
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
  }) {
    final estimator = _contextBudget.estimator;
    final system = _contextBudget.defaultSystemInstruction;
    final keyPointCount = constraints?.keyPointCount ?? _minKeyPoints;
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
        maxKeyPoints: _mapIntermediateMaxKeyPoints,
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
    required String stopReason,
  }) {
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
      retryable: true,
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
    bool mapStage = false,
    String? sourcePrompt,
    CorrectiveInferenceBudget? correctiveBudget,
  }) async {
    final extract = JsonOutputValidator.extractJsonObject(raw);
    var parsed = extract.object;
    if (parsed == null) {
      _logJsonRejection(
        extract: extract,
        mapStage: mapStage,
        stopReason: stopReason,
        truncated: truncated,
        correctiveBudget: correctiveBudget,
      );
    }
    final useLabeledFallback =
        labeledFallbackEnabled(sourcePrompt: sourcePrompt, mapStage: mapStage);
    if (parsed == null && useLabeledFallback) {
      if (correctiveBudget == null || correctiveBudget.consume()) {
        _logCorrectiveAttempt(
          action: 'labeled_fallback',
          mapStage: mapStage,
          stopReason: stopReason,
          truncated: truncated,
          correctiveBudget: correctiveBudget,
          rejectionReason: extract.rejectionReason,
        );
        parsed = await _runLabeledFallback(
          sourcePrompt: sourcePrompt!,
          signingKey: signingKey,
          keyPointCount: maxArrayItems,
        );
      } else {
        _log('[LABELED FALLBACK SKIPPED] corrective budget exhausted');
      }
    } else if (parsed == null) {
      if (correctiveBudget == null || correctiveBudget.consume()) {
        _logCorrectiveAttempt(
          action: 'json_repair',
          mapStage: mapStage,
          stopReason: stopReason,
          truncated: truncated,
          correctiveBudget: correctiveBudget,
          rejectionReason: extract.rejectionReason,
        );
        final repairPrompt = _jsonRepairPrompt(raw);
        if (repairPrompt != null) {
          final repaired = await _runPrompt(
            repairPrompt,
            signingKey: signingKey,
          );
          parsed = JsonOutputValidator.parseJsonObject(repaired);
          if (parsed == null) {
            _log('[JSON REPAIR FAILED] reason=repair_output_not_valid_json');
          }
        }
      } else {
        _log('[JSON REPAIR SKIPPED] corrective budget exhausted');
      }
    }
    if (parsed == null) {
      final reason = extract.rejectionReason ?? 'json_decode_failed';
      throw WorkerError(
        code: WorkerErrorCode.llmInvalidJson,
        message: mapStage
            ? 'Map chunk JSON could not be recovered locally '
                '(reason=$reason; stopReason=$stopReason)'
            : 'LLM output is not valid JSON after repair attempt '
                '(reason=$reason)',
        retryable: correctiveBudget == null,
        stage: WorkerTaskStage.llm,
      );
    }
    final summarizePath = correctiveBudget != null;
    if (!summarizePath) {
      parsed = JsonOutputValidator.coerceSchemaTypes(parsed, outputSchema);
    }
    if (truncated && mapStage) {
      throw WorkerError(
        code: WorkerErrorCode.outputSchemaMismatch,
        message:
            'Map chunk generation truncated before completion '
            '(stopReason=$stopReason)',
        retryable: true,
        stage: WorkerTaskStage.llm,
      );
    }
    if (truncated) {
      // The runtime stop cut the reply, so the trailing fields never arrived.
      // Completing the shape keeps the extracted facts and leaves the content
      // to the quality repair; the model did not actually break the contract.
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
    if (!limit.treatAsSuccess && !summarizePath) {
      // A reply that repeats itself until the output budget runs out is valid
      // JSON that simply carries too many items. Cutting it to the contract
      // limits here keeps the fields the model did fill in; asking the model
      // to compact it returns the same repetition and loses them.
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
    if (!limit.treatAsSuccess) {
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
  }) async {
    final body = PromptTemplates.delimitedBody(sourcePrompt);
    if (body == null || body.isEmpty) {
      return null;
    }
    // One chunk cannot supply the customer's full key point count; the reduce
    // stage assembles it from the partials. `Chunk metadata:` only appears in
    // the map template.
    final requestedPoints = sourcePrompt.contains('Chunk metadata:')
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
        final mapStage = sourcePrompt.contains('Chunk metadata:');
        if (parsed != null && mapStage) {
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

  Future<String> _runPrompt(String prompt, {required String signingKey}) async {
    final reply = await _runPromptReply(prompt, signingKey: signingKey);
    return reply.text;
  }

  Future<_PromptReply> _runPromptReply(
    String prompt, {
    required String signingKey,
  }) async {
    final formatted = FormattedPromptBuilder.buildTaskPrompt(
      templateBody: prompt,
      systemInstruction: _contextBudget.defaultSystemInstruction,
    );
    _contextBudget.ensureDirectInferenceOrThrow(
      prompt: prompt,
      maxOutputTokens: config.maxOutputTokens,
    );
    final runner = _runner;
    if (runner != null) {
      return _PromptReply(text: await runner(formatted), truncated: false);
    }
    await ensureLoaded(signingKey: signingKey);
    final output = await _adapter.run(
      inputBytes: Uint8List.fromList(utf8.encode(prompt)),
      resumedState: null,
    );
    final stopReason = output.metrics['stopReason']?.toString() ?? 'model_eos';
    return _PromptReply(
      text: utf8.decode(output.resultBytes),
      // Both stops cut the reply before the model closed the object, so the
      // trailing fields have to be completed locally.
      truncated: stopReason == 'output_limit' || stopReason == 'repetition',
      stopReason: stopReason,
    );
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
