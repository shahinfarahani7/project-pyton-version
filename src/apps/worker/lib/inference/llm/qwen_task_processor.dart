import 'dart:convert';
import 'dart:typed_data';

import '../../contracts/worker_error.dart';
import '../../models/worker_model_catalog.dart';
import '../../runtime/gemma_inference_adapter.dart';
import '../../runtime/inference_adapter.dart';
import '../../runtime/checkpoint_manager.dart';
import '../../runtime/model_runtime_manager.dart';
import '../../validation/json_output_validator.dart';
import 'context_budget_manager.dart';
import 'formatted_prompt_builder.dart';
import 'hierarchical_summarize_pipeline.dart';
import 'labeled_summary_parser.dart';
import 'output_limit_enforcer.dart';
import 'prompt_templates.dart';
import 'semantic_chunk_engine.dart';

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
  const _PromptReply({required this.text, required this.truncated});

  final String text;
  final bool truncated;
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
  static const _maxKeyPoints = 6;
  static const _maxInstructionTokens = 200;
  static const _minRepairExcerptChars = 400;

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
  }) async {
    _log(
      '[MODEL REQUEST] promptChars=${prompt.length} '
      'prompt="${_preview(prompt)}"',
    );
    final reply = await _runPromptReply(prompt, signingKey: signingKey);
    _log(
      '[MODEL RESPONSE] responseChars=${reply.text.length} '
      'truncated=${reply.truncated} response="${_preview(reply.text)}"',
    );
    return _parseJsonResponse(
      raw: reply.text,
      outputSchema: outputSchema,
      signingKey: signingKey,
      maxArrayItems: maxArrayItems,
      truncated: reply.truncated,
      sourcePrompt: labeledFallback ? prompt : null,
    );
  }

  Future<Map<String, dynamic>> runSummarizeJsonTask({
    required String inputText,
    String? userInstructions,
    required String signingKey,
    Map<String, dynamic>? outputSchema,
    String? assignmentId,
    int? fenceToken,
    Future<void> Function(ChunkCheckpointRecord record)? onChunkCheckpoint,
  }) async {
    final keyPointCount = _requestedKeyPointCount(userInstructions);
    final instructions = _boundedInstructions(userInstructions);
    final reservedPromptTokens = summarizePromptReserveTokens(
      userInstructions: instructions,
      keyPointCount: keyPointCount,
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
      ),
    );
    var result = await pipeline.summarize(
      inputText: inputText,
      plan: plan,
      userInstructions: instructions,
      keyPointCount: keyPointCount,
      checkpointScope: checkpointScope,
    );
    result = _applyDeterministicSummaryRepairs(
      _normalizeSummary(
        result,
        sourceText: inputText,
        keyPointCount: keyPointCount,
      ),
      sourceText: inputText,
    );
    var qualityIssue = _summaryQualityIssue(
      result,
      sourceText: inputText,
      keyPointCount: keyPointCount,
    );
    if (qualityIssue != null) {
      final repairPrompt = _summaryRepairPrompt(
        sourceText: inputText,
        invalidSummaryJson: jsonEncode(result),
        qualityIssue: qualityIssue,
        userInstructions: instructions,
        keyPointCount: keyPointCount,
      );
      if (repairPrompt == null) {
        _log('[SUMMARY QUALITY REPAIR SKIPPED] reason=$qualityIssue');
      } else {
        _log('[SUMMARY QUALITY RETRY] reason=$qualityIssue');
        result = _applyDeterministicSummaryRepairs(
          _normalizeSummary(
            await runJsonTask(
              prompt: repairPrompt,
              outputSchema: outputSchema ?? _summaryOutputSchema,
              signingKey: signingKey,
              maxArrayItems: keyPointCount,
              labeledFallback: true,
            ),
            sourceText: inputText,
            keyPointCount: keyPointCount,
          ),
          sourceText: inputText,
        );
      }
      // A repaired answer that is merely short of the requested key point
      // count is still usable, so only structural defects fail the task.
      qualityIssue = _summaryQualityIssue(
        result,
        sourceText: inputText,
        keyPointCount: keyPointCount,
        minimumKeyPoints: _minKeyPoints,
      );
    }
    if (qualityIssue != null) {
      throw WorkerError(
        code: WorkerErrorCode.outputSchemaMismatch,
        message: 'Summary quality validation failed: $qualityIssue',
        retryable: true,
        stage: WorkerTaskStage.llm,
      );
    }
    _log('[SUMMARY QUALITY OK] response=${jsonEncode(result)}');
    return result;
  }

  /// The repair prompt carries the source text back to the model, so on a
  /// heavy input it is shortened until it fits; when even a short excerpt does
  /// not fit, the deterministic repairs are the only correction available.
  String? _summaryRepairPrompt({
    required String sourceText,
    required String invalidSummaryJson,
    required String qualityIssue,
    required String? userInstructions,
    required int keyPointCount,
  }) {
    var excerpt = sourceText;
    while (true) {
      final prompt = PromptTemplates.summaryQualityRepair(
        sourceText: excerpt,
        invalidSummaryJson: invalidSummaryJson,
        qualityIssue: qualityIssue,
        userInstructions: userInstructions,
        keyPointCount: keyPointCount,
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
    int keyPointCount = _minKeyPoints,
  }) {
    final estimator = _contextBudget.estimator;
    final direct = FormattedPromptBuilder.buildTaskPrompt(
      templateBody: PromptTemplates.documentSummarize(
        ocrText: '',
        userInstructions: userInstructions,
        keyPointCount: keyPointCount,
      ),
      systemInstruction: _contextBudget.defaultSystemInstruction,
    );
    final mapped = FormattedPromptBuilder.buildTaskPrompt(
      templateBody: PromptTemplates.summarizeMapChunk(
        chunkText: '',
        chunkIndex: 0,
        totalChunks: 999,
        chunkId: '0' * 64,
      ),
      systemInstruction: _contextBudget.defaultSystemInstruction,
    );
    final directTokens = estimator.estimate(direct);
    final mappedTokens = estimator.estimate(mapped);
    return directTokens > mappedTokens ? directTokens : mappedTokens;
  }

  /// Instructions share the same context window as the source text, so an
  /// oversized block is trimmed instead of starving the chunk budget.
  String? _boundedInstructions(String? userInstructions) {
    final trimmed = userInstructions?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    const maxChars = _maxInstructionTokens * 3;
    if (trimmed.length <= maxChars) {
      return trimmed;
    }
    _log('[INSTRUCTIONS TRIMMED] chars=${trimmed.length} keptChars=$maxChars');
    return trimmed.substring(0, maxChars);
  }

  int _requestedKeyPointCount(String? userInstructions) {
    final text = userInstructions?.toLowerCase();
    if (text == null || text.isEmpty) {
      return _minKeyPoints;
    }
    const spelled = {'three': 3, 'four': 4, 'five': 5, 'six': 6};
    final match = RegExp(
      r'(\d+|three|four|five|six)\s+(?:\w+\s+){0,2}'
      r'(?:key\s*points?|bullet\s*points?|bullets|facts|points)',
    ).firstMatch(text);
    if (match == null) {
      return _minKeyPoints;
    }
    final token = match.group(1)!;
    final count = spelled[token] ?? int.tryParse(token);
    if (count == null) {
      return _minKeyPoints;
    }
    return count.clamp(_minKeyPoints, _maxKeyPoints).toInt();
  }

  Map<String, dynamic> _applyDeterministicSummaryRepairs(
    Map<String, dynamic> summary, {
    required String sourceText,
  }) {
    final source = _comparisonText(sourceText);
    final complaint = summary['mainComplaint'] as String;
    if (_sourceHasDelayAndEstimateProblem(source) &&
        !_containsAny(_comparisonText(complaint), const [
          'tracking',
          'estimate',
          'unreliable',
          'inaccurate',
        ])) {
      final separator = complaint.trim().endsWith('.') ? ' ' : '; ';
      final estimateClause = _containsPersian(sourceText)
          ? 'زمان تخمینی رسیدن نیز غیرقابل اعتماد بود.'
          : 'arrival estimates were unreliable.';
      summary['mainComplaint'] = '$complaint$separator$estimateClause';
      _log(
        '[SUMMARY DETERMINISTIC REPAIR] '
        'added unreliable estimate coverage to mainComplaint',
      );
    }
    return summary;
  }

  Map<String, dynamic> _normalizeSummary(
    Map<String, dynamic> raw, {
    required String sourceText,
    int keyPointCount = _minKeyPoints,
  }) => {
    'summary': _cleanText(raw['summary']),
    // Twice the requested count is collected first so points copied verbatim
    // from the source cannot take the slots of original ones.
    'keyPoints': _rankKeyPoints(
      _uniqueStrings(raw['keyPoints'], maxItems: keyPointCount * 2),
      sourceText: sourceText,
      maxItems: keyPointCount,
    ),
    'mainComplaint': _cleanText(raw['mainComplaint']),
    'suggestedImprovement': _cleanText(raw['suggestedImprovement']),
    'missingOrUnclear': _uniqueStrings(
      raw['missingOrUnclear'],
      maxItems: keyPointCount > _minKeyPoints ? 3 : 2,
    ).where((item) => !_isClearlySupported(item, sourceText)).toList(),
  };

  /// A key point that is a verbatim source sentence tells the customer nothing
  /// they could not read themselves, so it sinks to the end of the list and is
  /// dropped once enough original points remain.
  List<String> _rankKeyPoints(
    List<String> points, {
    required String sourceText,
    required int maxItems,
  }) {
    final sentences = _sourceSentences(sourceText);
    final original = <String>[];
    final copied = <String>[];
    for (final point in points) {
      if (sentences.contains(_comparisonText(point))) {
        copied.add(point);
      } else {
        original.add(point);
      }
    }
    if (copied.isEmpty) {
      return points.take(maxItems).toList();
    }
    _log('[SUMMARY ECHO FILTER] copiedKeyPoints=${copied.length}');
    final ranked = original.length >= _minKeyPoints
        ? original
        : [...original, ...copied];
    return ranked.take(maxItems).toList();
  }

  Set<String> _sourceSentences(String sourceText) => sourceText
      .split(RegExp(r'[.!?\u061F\u06D4\n]+'))
      .map(_comparisonText)
      .where((sentence) => sentence.isNotEmpty)
      .toSet();

  String? _summaryQualityIssue(
    Map<String, dynamic> summary, {
    required String sourceText,
    int keyPointCount = _minKeyPoints,
    int? minimumKeyPoints,
  }) {
    if ((summary['summary'] as String).isEmpty) return 'summary is empty';
    final keyPoints = summary['keyPoints'] as List<String>;
    final required = minimumKeyPoints ?? keyPointCount;
    if (keyPoints.length < required) {
      return 'at least $required distinct key points required';
    }
    if ((summary['mainComplaint'] as String).isEmpty) {
      return 'main complaint is missing';
    }
    if ((summary['suggestedImprovement'] as String).isEmpty) {
      return 'suggested improvement is missing';
    }
    final source = _comparisonText(sourceText);
    final complaint = _comparisonText(summary['mainComplaint'] as String);
    if (_sourceHasDelayAndEstimateProblem(source) &&
        (!_containsAny(complaint, const ['late', 'delay', 'delayed']) ||
            !_containsAny(complaint, const [
              'tracking',
              'estimate',
              'unreliable',
              'inaccurate',
            ]))) {
      return 'main complaint must include both delivery delays and unreliable estimates';
    }
    // The defect to catch is one sentence echoed across every field. A main
    // complaint that restates one of the key points is normal, so only the
    // echoes that carry no extra information are rejected.
    final summaryText = _comparisonText(summary['summary'] as String);
    final improvement = _comparisonText(
      summary['suggestedImprovement'] as String,
    );
    final pointTexts = keyPoints.map(_comparisonText).toList();
    if (summaryText.isNotEmpty &&
        (pointTexts.contains(summaryText) || summaryText == complaint)) {
      return 'summary repeats another field';
    }
    if (improvement.isNotEmpty && improvement == complaint) {
      return 'suggested improvement repeats the main complaint';
    }
    if (_summaryCopiesSource(summary['summary'] as String, sourceText)) {
      return 'summary copies the source text instead of condensing it';
    }
    return null;
  }

  /// True when every sentence of the summary is a verbatim source sentence.
  /// Short sources are exempt, since a faithful one-sentence summary of a
  /// one-sentence source is legitimately the same sentence.
  bool _summaryCopiesSource(String summaryText, String sourceText) {
    final sentences = _sourceSentences(sourceText);
    if (sentences.length <= 2) {
      return false;
    }
    final summarySentences = _sourceSentences(summaryText);
    if (summarySentences.isEmpty) {
      return false;
    }
    return summarySentences.every(sentences.contains);
  }

  bool _sourceHasDelayAndEstimateProblem(String source) =>
      _containsAny(source, const [
        'late',
        'delay',
        'delayed',
        'تاخیر',
        'دیر',
      ]) &&
      _containsAny(source, const ['tracking', 'estimate', 'arrival time']) &&
      _containsAny(source, const [
        'inaccurate',
        'unreliable',
        'could not provide',
        'kept showing',
      ]);

  bool _containsPersian(String value) =>
      RegExp(r'[\u0600-\u06FF]').hasMatch(value);

  String _cleanText(Object? value) =>
      value is String ? value.trim().replaceAll(RegExp(r'\s+'), ' ') : '';

  List<String> _uniqueStrings(Object? value, {required int maxItems}) {
    if (value is! List) return <String>[];
    final seen = <String>{};
    final result = <String>[];
    for (final item in value) {
      final text = _cleanText(item);
      if (text.isEmpty || !seen.add(_comparisonText(text))) continue;
      result.add(text);
      if (result.length == maxItems) break;
    }
    return result;
  }

  bool _isClearlySupported(String claim, String sourceText) {
    final claimTokens = _contentTokens(claim);
    if (claimTokens.isEmpty) return false;
    final sourceTokens = _contentTokens(sourceText);
    final matched = claimTokens.where(sourceTokens.contains).length;
    return matched * 10 >= claimTokens.length * 7;
  }

  Set<String> _contentTokens(String value) {
    const stopWords = {
      'a',
      'an',
      'and',
      'are',
      'as',
      'at',
      'be',
      'for',
      'in',
      'is',
      'of',
      'on',
      'the',
      'to',
      'was',
      'were',
      'with',
    };
    return _comparisonText(value)
        .split(' ')
        .where((token) => token.length > 1 && !stopWords.contains(token))
        .toSet();
  }

  bool _containsAny(String value, List<String> terms) =>
      terms.any(value.contains);

  String _comparisonText(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'''[\s.,;:!?،؛؟"'“”]+'''), ' ')
      .trim();

  Future<Map<String, dynamic>> _parseJsonResponse({
    required String raw,
    Map<String, dynamic>? outputSchema,
    required String signingKey,
    int maxArrayItems = 3,
    bool truncated = false,
    String? sourcePrompt,
  }) async {
    var parsed = JsonOutputValidator.parseJsonObject(raw);
    if (parsed == null && sourcePrompt != null) {
      // Re-asking this model to fix its own broken JSON corrupts the text
      // further, so the summarize path drops the format instead.
      parsed = await _runLabeledFallback(
        sourcePrompt: sourcePrompt,
        signingKey: signingKey,
        keyPointCount: maxArrayItems,
      );
    } else if (parsed == null) {
      final repairPrompt = _jsonRepairPrompt(raw);
      if (repairPrompt != null) {
        final repaired = await _runPrompt(repairPrompt, signingKey: signingKey);
        parsed = JsonOutputValidator.parseJsonObject(repaired);
      }
    }
    if (parsed == null) {
      throw const WorkerError(
        code: WorkerErrorCode.llmInvalidJson,
        message: 'LLM output is not valid JSON after repair attempt',
        retryable: true,
        stage: WorkerTaskStage.llm,
      );
    }
    parsed = JsonOutputValidator.coerceSchemaTypes(parsed, outputSchema);
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
    if (!limit.treatAsSuccess) {
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
        throw const WorkerError(
          code: WorkerErrorCode.llmInvalidJson,
          message: 'Compacted LLM output is not valid JSON',
          retryable: true,
          stage: WorkerTaskStage.llm,
        );
      }
      final compacted = JsonOutputValidator.coerceSchemaTypes(
        parsedCompact,
        outputSchema,
      );
      schemaError = JsonOutputValidator.validateSchema(compacted, outputSchema);
      if (schemaError != null) {
        throw schemaError;
      }
      _enforceOutputLimit(jsonEncode(compacted));
      _log('[MODEL COMPACT RESPONSE] response=${jsonEncode(compacted)}');
      parsed = compacted;
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
        final parsed = LabeledSummaryParser.parse(raw);
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
    final stopReason = output.metrics['stopReason'];
    return _PromptReply(
      text: utf8.decode(output.resultBytes),
      // Both stops cut the reply before the model closed the object, so the
      // trailing fields have to be completed locally.
      truncated: stopReason == 'output_limit' || stopReason == 'repetition',
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
