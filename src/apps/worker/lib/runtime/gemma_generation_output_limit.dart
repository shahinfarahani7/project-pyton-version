import '../inference/llm/context_budget_manager.dart';
import '../validation/json_stream_boundary.dart';
import '../validation/output_repetition_guard.dart';
import 'device_inference_policy_config.dart';
import 'gemma_stage_merger.dart';
import 'long_form_execution_budget.dart';
import 'long_form_section_plan.dart';
import 'worker_pipeline_log.dart';

/// Output-generation cap for Gemma. This is separate from the LiteRT context
/// window (`maxTokens` / KV cache, 2048 in benchmark mode).
abstract final class GemmaGenerationOutputLimit {
  /// Short/default free-form answer. Also the per-stage cap for long-form.
  /// The number lives in [TierPolicyTable.t2], the central device lookup.
  static final textDirectShort = const TierPolicyTable().t2.shortOutput;

  /// Medium answer: explain, elaborate, or a normally detailed reply.
  static final textDirectMedium = const TierPolicyTable().t2.mediumOutput;

  /// Explicitly detailed or extended answer, still one session.
  static final textDirectDetailed = const TierPolicyTable().t2.detailedOutput;

  /// Kept as the short/default cap. Not the long-form session size.
  static final textDirect = textDirectShort;

  static final longFormMaxStages = const TierPolicyTable().t2.maxStages;
  static final longFormHardMaxStages = const TierPolicyTable().t2.hardMaxStages;

  static const eos = 'EOS';
  static const outputLimit = 'OUTPUT_LIMIT';
  static const longFormStageLimit = 'LONG_FORM_STAGE_LIMIT';
  static const leaseBudgetExhausted = 'LEASE_BUDGET_EXHAUSTED';
  static const cancelled = 'CANCELLED';
  static const error = 'ERROR';

  /// Retired catalog default injected into every dev manifest. It is not a
  /// caller override; text.direct must not fall back to it after resolution.
  static const legacyCatalogCap = 256;

  /// Classification, first match wins:
  /// 1. long-form (article/essay/report/page count, or options.longForm)
  ///    uses staged sessions of [textDirectShort], never one large session.
  /// 2. explicitly detailed/extended → [textDirectDetailed] (512).
  /// 3. medium/detailed → [textDirectMedium] (384).
  /// 4. otherwise short/default → [textDirectShort] (256).
  /// An explicit maxOutputTokens other than [legacyCatalogCap] replaces the
  /// numeric cap and stays a single session.
  static GemmaOutputLimitDecision resolveTextDirect({
    required String prompt,
    int? explicitMaxOutputTokens,
    bool maxOutputTokensSpecified = false,
    bool longForm = false,
  }) {
    final answerClass = classifyAnswer(prompt, longForm: longForm);
    final requested = switch (answerClass) {
      'medium' => textDirectMedium,
      'detailed' => textDirectDetailed,
      _ => textDirectShort,
    };
    final specified = maxOutputTokensSpecified &&
        explicitMaxOutputTokens != null &&
        explicitMaxOutputTokens > 0 &&
        explicitMaxOutputTokens != legacyCatalogCap;
    if (specified) {
      return GemmaOutputLimitDecision(
        answerClass: answerClass,
        requestedOutputLimit: requested,
        effectiveOutputLimit: explicitMaxOutputTokens,
        staged: false,
        source: 'explicit',
      );
    }
    return GemmaOutputLimitDecision(
      answerClass: answerClass,
      requestedOutputLimit: requested,
      effectiveOutputLimit: requested,
      staged: answerClass == 'long-form',
      source: answerClass,
    );
  }

  static String classifyAnswer(String prompt, {bool longForm = false}) {
    if (longForm || requestsLongForm(prompt)) {
      return 'long-form';
    }
    if (requestsExplicitlyDetailed(prompt)) {
      return 'detailed';
    }
    if (requestsMediumDetail(prompt)) {
      return 'medium';
    }
    return 'short';
  }

  /// Text-only `text.direct` uses [textDirect] unless the prompt or options
  /// ask for a long article.
  static int forTextDirect({
    required String prompt,
    int? explicitMaxOutputTokens,
    bool maxOutputTokensSpecified = false,
    bool longForm = false,
  }) {
    return resolveTextDirect(
      prompt: prompt,
      explicitMaxOutputTokens: explicitMaxOutputTokens,
      maxOutputTokensSpecified: maxOutputTokensSpecified ||
          (explicitMaxOutputTokens != null && explicitMaxOutputTokens != legacyCatalogCap),
      longForm: longForm,
    ).effectiveOutputLimit;
  }

  /// Explicitly detailed or extended. Checked before the medium cues so
  /// "very detailed" and "با جزئیات زیاد" do not stop at 384.
  static bool requestsExplicitlyDetailed(String prompt) {
    final normalized = prompt.toLowerCase();
    const english = [
      'very detailed',
      'in depth',
      'in-depth',
      'extended',
      'comprehensive',
      'lengthy',
      'thorough',
      'long answer',
    ];
    if (english.any((cue) => normalized.contains(cue))) {
      return true;
    }
    const persian = [
      'خیلی مفصل',
      'با جزئیات زیاد',
      'طولانی',
      'گسترده',
    ];
    return persian.any((cue) => prompt.contains(cue));
  }

  /// A fuller answer that is not an article and not an explicit extended one.
  static bool requestsMediumDetail(String prompt) {
    final normalized = prompt.toLowerCase();
    const english = [
      'detailed',
      'in detail',
      'elaborate',
      'explain',
      'step by step',
      'step-by-step',
    ];
    if (english.any((cue) => normalized.contains(cue))) {
      return true;
    }
    const persian = [
      'مفصل',
      'با جزئیات',
      'توضیح',
      'شرح',
      'قدم به قدم',
      'مرحله به مرحله',
    ];
    return persian.any((cue) => prompt.contains(cue));
  }

  static bool requestsLongForm(String prompt) {
    final normalized = _normalizeDigits(prompt).toLowerCase();
    if (normalized.contains('long-form') ||
        normalized.contains('long form') ||
        normalized.contains('article') ||
        normalized.contains('essay') ||
        normalized.contains('report') ||
        normalized.contains('مقاله') ||
        normalized.contains('گزارش') ||
        normalized.contains('انشا')) {
      return true;
    }
    return RegExp(r'\b\d+\s*-?\s*pages?\b').hasMatch(normalized) ||
        RegExp(r'\d+\s*صفحه').hasMatch(normalized);
  }

  static String _normalizeDigits(String text) {
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final persianIndex = persian.indexOf(char);
      if (persianIndex >= 0) {
        buffer.write(persianIndex);
        continue;
      }
      final arabicIndex = arabicIndic.indexOf(char);
      if (arabicIndex >= 0) {
        buffer.write(arabicIndex);
        continue;
      }
      buffer.write(char);
    }
    return buffer.toString();
  }

  /// Native LiteRT stops the stream when `maxOutputTokens` chunks are emitted
  /// and does not label that stop. A full chunk count is an output limit, not EOS.
  static String finalizeStopReason({
    required String provisional,
    required int generatedChunks,
    required int configuredOutputLimit,
  }) {
    switch (provisional) {
      case outputLimit:
      case 'output_limit':
        return outputLimit;
      case cancelled:
      case 'cancelled':
        return cancelled;
      case error:
      case 'error':
        return error;
      case 'model_eos':
      case eos:
        if (generatedChunks >= configuredOutputLimit) {
          return outputLimit;
        }
        return eos;
      default:
        return provisional;
    }
  }
}

class GemmaOutputLimitDecision {
  const GemmaOutputLimitDecision({
    required this.answerClass,
    required this.requestedOutputLimit,
    required this.effectiveOutputLimit,
    required this.staged,
    required this.source,
  });

  /// `short`, `medium`, `detailed`, or `long-form`.
  final String answerClass;
  final int requestedOutputLimit;
  final int effectiveOutputLimit;

  /// Long-form runs several sessions of [effectiveOutputLimit], not one large one.
  final bool staged;

  /// `explicit`, or the same value as [answerClass].
  final String source;

  bool get detectedLongForm => answerClass == 'long-form';

  String get logLine =>
      '[OUTPUT LIMIT] answerClass=$answerClass '
      'effectiveOutputLimit=$effectiveOutputLimit '
      'staged=$staged '
      'source=$source';

  String completionLog({
    required int generatedChunks,
    required int generatedTokens,
    required bool truncated,
  }) =>
      '[OUTPUT LIMIT] answerClass=$answerClass '
      'effectiveOutputLimit=$effectiveOutputLimit '
      'generatedChunks=$generatedChunks '
      'generatedTokens=$generatedTokens '
      'truncated=$truncated';
}

class GemmaStagePiece {
  const GemmaStagePiece({
    required this.text,
    required this.stopReason,
    required this.generatedChunks,
    required this.generatedTokens,
    this.complete = true,
    this.truncated = false,
    this.stagesUsed = 1,
  });

  final String text;
  final String stopReason;
  final int generatedChunks;
  final int generatedTokens;
  final bool complete;
  final bool truncated;
  final int stagesUsed;

  bool get hitOutputLimit => stopReason == GemmaGenerationOutputLimit.outputLimit;
}

/// Decides whether another long-form stage is required.
///
/// A stage is incomplete when it stopped on [GemmaGenerationOutputLimit.outputLimit]
/// and the text is cut mid-sentence, the last block is unfinished, or a heading
/// or list item is still open. EOS, or text that is structurally finished, stops
/// the loop. [GemmaGenerationOutputLimit.longFormMaxStages] is only the default
/// budget; generation may continue until [GemmaGenerationOutputLimit.longFormHardMaxStages].
class LongFormCompletion {
  static LongFormCompletionDecision evaluate({
    required String text,
    required String stopReason,
    required int stagesUsed,
    required int maxStages,
    required int hardMaxStages,
    bool completionMarkerFound = false,
    bool plannedSectionsComplete = false,
  }) {
    final eos = stopReason == GemmaGenerationOutputLimit.eos || stopReason == 'model_eos';
    final hitLimit = stopReason == GemmaGenerationOutputLimit.outputLimit ||
        stopReason == 'output_limit';
    final documentComplete = eos || completionMarkerFound || plannedSectionsComplete;
    final endedIncomplete = !documentComplete && textIsIncomplete(text);
    final shouldContinue = !documentComplete && hitLimit && stagesUsed < hardMaxStages;
    final truncated = !documentComplete && !shouldContinue && text.trim().isNotEmpty;
    return LongFormCompletionDecision(
      endedIncomplete: endedIncomplete,
      shouldContinue: shouldContinue,
      complete: documentComplete,
      truncated: truncated,
      finalStopReason: truncated ? GemmaGenerationOutputLimit.longFormStageLimit : stopReason,
      maxStages: maxStages,
      hardMaxStages: hardMaxStages,
    );
  }

  /// Mid-sentence cuts, an unfinished last block, or an open heading/list item.
  static bool textIsIncomplete(String text) {
    final trimmed = text.trimRight();
    if (trimmed.isEmpty) {
      return true;
    }
    if (_openHeadingOrList(trimmed)) {
      return true;
    }
    return !_endsWithSentence(trimmed);
  }

  static bool _endsWithSentence(String text) {
    const terminators = {'.', '!', '?', '؟', '。', '…'};
    return terminators.contains(text[text.length - 1]);
  }

  static bool _openHeadingOrList(String text) {
    final lastLine = text.trimRight().split('\n').last.trim();
    if (lastLine.isEmpty) {
      return true;
    }
    final headingOnly = RegExp(r'^#{1,6}\s+\S').hasMatch(lastLine) ||
        RegExp(r'^\*\*.+\*\*:?\s*$').hasMatch(lastLine);
    if (headingOnly) {
      return true;
    }
    final listItem = RegExp(r'^(?:[-*+]\s+|(?:\d+|[۰-۹]+)[\.\)])').hasMatch(lastLine);
    return listItem && !_endsWithSentence(lastLine);
  }
}

class LongFormCompletionDecision {
  const LongFormCompletionDecision({
    required this.endedIncomplete,
    required this.shouldContinue,
    required this.complete,
    required this.truncated,
    required this.finalStopReason,
    required this.maxStages,
    required this.hardMaxStages,
  });

  final bool endedIncomplete;
  final bool shouldContinue;
  final bool complete;
  final bool truncated;
  final String finalStopReason;
  final int maxStages;
  final int hardMaxStages;

  String logLine(int stageIndex, String stopReason) =>
      '[LONG FORM COMPLETION] stageIndex=$stageIndex '
      'stopReason=$stopReason '
      'endedIncomplete=$endedIncomplete '
      'shouldContinue=$shouldContinue '
      'maxStages=$maxStages '
      'hardMaxStages=$hardMaxStages';

  String finalLog(int stagesUsed) =>
      '[LONG FORM FINAL] complete=$complete '
      'truncated=$truncated '
      'stagesUsed=$stagesUsed '
      'finalStopReason=$finalStopReason';
}

/// Long-form continues in fresh sessions of the stage cap. Each session closes
/// before the next one opens; the resident model is not reloaded here.
class GemmaStagedDirectGeneration {
  static Future<GemmaStagePiece> run({
    required GemmaOutputLimitDecision decision,
    required String prompt,
    required Future<GemmaStagePiece> Function(int stageIndex, String stagePrompt) generateStage,
    TokenEstimator estimator = const TokenEstimator(),
    int? maxStages,
    int? hardMaxStages,
    LongFormExecutionBudget? executionBudget,
    LongFormRuntimeSignals Function()? readSignals,
    int Function()? readElapsedMs,
  }) async {
    if (!decision.staged) {
      return generateStage(0, prompt);
    }

    final stageBudget = maxStages ??
        executionBudget?.maxStages ??
        GemmaGenerationOutputLimit.longFormMaxStages;
    final hardBudget = hardMaxStages ??
        executionBudget?.hardMaxStages ??
        GemmaGenerationOutputLimit.longFormHardMaxStages;
    final safetyLimit = hardBudget < 1 ? 1 : hardBudget;

    var accumulated = '';
    var generatedChunks = 0;
    var stopReason = GemmaGenerationOutputLimit.eos;
    var completion = LongFormCompletion.evaluate(
      text: '',
      stopReason: stopReason,
      stagesUsed: 0,
      maxStages: stageBudget,
      hardMaxStages: safetyLimit,
    );
    var stagesUsed = 0;
    final progress = LongFormSectionProgress(LongFormSectionPlan.sectionsFor(prompt));
    final executionClock = Stopwatch()..start();
    int elapsedNow() => readElapsedMs?.call() ?? executionClock.elapsedMilliseconds;
    for (var stage = 0; stage < safetyLimit; stage++) {
      if (stage > 0 && executionBudget != null) {
        final base = readSignals?.call() ?? executionBudget.initialSignals;
        final gate = executionBudget.evaluate(
          stageIndex: stage,
          stageCount: stage,
          signals: LongFormRuntimeSignals(
            elapsedMs: elapsedNow(),
            leaseRemainingMs: base.leaseRemainingMs,
            batteryPercent: base.batteryPercent,
            isCharging: base.isCharging,
            thermalState: base.thermalState,
          ),
        );
        if (!gate.shouldContinue) {
          final incomplete = LongFormCompletion.textIsIncomplete(accumulated);
          final leaseStop = gate.reason == 'lease_budget_exhausted';
          completion = LongFormCompletionDecision(
            endedIncomplete: incomplete,
            shouldContinue: false,
            complete: false,
            truncated: incomplete || leaseStop,
            finalStopReason: leaseStop
                ? GemmaGenerationOutputLimit.leaseBudgetExhausted
                : (incomplete
                    ? GemmaGenerationOutputLimit.longFormStageLimit
                    : stopReason),
            maxStages: stageBudget,
            hardMaxStages: safetyLimit,
          );
          break;
        }
      }
      final previousEndedIncomplete = stage > 0 &&
          LongFormCompletion.textIsIncomplete(accumulated);
      final tail = stage == 0
          ? ''
          : GemmaStageMerger.continuationTail(
              accumulated,
              endedIncomplete: previousEndedIncomplete,
            );
      final stagePrompt = _stagePrompt(
        stage: stage,
        original: prompt,
        tail: tail,
        progress: progress,
      );
      final piece = await generateStage(stage, stagePrompt);
      final markerFound = LongFormOutputSanitizer.hasRealCompletionMarker(piece.text);
      final cleanedText = LongFormOutputSanitizer.sanitize(
        LongFormSectionPlan.stripMarker(piece.text),
        originalPrompt: prompt,
        plannedSections: progress.plannedSections,
      );
      generatedChunks += piece.generatedChunks;
      stopReason = markerFound ? GemmaGenerationOutputLimit.eos : piece.stopReason;
      stagesUsed = stage + 1;
      if (cleanedText.trim().isEmpty && !markerFound) {
        _logStage(
          stageIndex: stage,
          stageInputTailChars: tail.length,
          stageOutputChars: cleanedText.length,
          overlapRemovedChars: 0,
          duplicateBlocksRemoved: 0,
          previousEndedIncomplete: previousEndedIncomplete,
          stageStopReason: piece.stopReason,
        );
        completion = LongFormCompletion.evaluate(
          text: accumulated,
          stopReason: stopReason,
          stagesUsed: stagesUsed,
          maxStages: stageBudget,
          hardMaxStages: safetyLimit,
          completionMarkerFound: markerFound,
          plannedSectionsComplete: progress.plannedSectionsComplete,
        );
        WorkerPipelineLog.info(WorkerPipelineLog.exec, completion.logLine(stage, piece.stopReason));
        break;
      }
      final prepared = LongFormSectionPlan.removeDuplicateSections(
        text: cleanedText,
        plannedSections: progress.plannedSections,
        completedSections: progress.completedSections,
        previousText: accumulated,
        currentSectionIndex: progress.currentIndex,
      );
      final merge = stage == 0
          ? GemmaStageMerge(
              text: prepared.text.trimRight(),
              overlapRemovedChars: 0,
              duplicateBlocksRemoved: prepared.removedSections,
            )
          : GemmaStageMerger.merge(
              previousText: accumulated,
              nextText: prepared.text,
              previousEndedIncomplete: previousEndedIncomplete,
              completedSectionTitles: progress.completedSections,
              plannedSectionTitles: progress.plannedSections,
              currentSectionIndex: progress.currentIndex,
            );
      _logStage(
        stageIndex: stage,
        stageInputTailChars: tail.length,
        stageOutputChars: cleanedText.length,
        overlapRemovedChars: merge.overlapRemovedChars,
        duplicateBlocksRemoved: merge.duplicateBlocksRemoved,
        previousEndedIncomplete: previousEndedIncomplete,
        stageStopReason: piece.stopReason,
      );
      final madeProgress = stage == 0 || merge.text != accumulated;
      accumulated = LongFormOutputSanitizer.sanitize(
        LongFormSectionPlan.stripMarker(merge.text),
        originalPrompt: prompt,
        plannedSections: progress.plannedSections,
      );
      if (!markerFound) {
        progress.observe(prepared.text);
      }
      completion = LongFormCompletion.evaluate(
        text: accumulated,
        stopReason: stopReason,
        stagesUsed: stagesUsed,
        maxStages: stageBudget,
        hardMaxStages: safetyLimit,
        completionMarkerFound: markerFound,
        plannedSectionsComplete: progress.plannedSectionsComplete,
      );
      final shouldContinue = completion.shouldContinue && madeProgress;
      final logged = LongFormCompletionDecision(
        endedIncomplete: completion.endedIncomplete,
        shouldContinue: shouldContinue,
        complete: completion.complete,
        truncated: !completion.complete && !shouldContinue,
        finalStopReason: !completion.complete && !shouldContinue
            ? GemmaGenerationOutputLimit.longFormStageLimit
            : stopReason,
        maxStages: stageBudget,
        hardMaxStages: safetyLimit,
      );
      WorkerPipelineLog.info(WorkerPipelineLog.exec, logged.logLine(stage, piece.stopReason));
      completion = logged;
      if (!shouldContinue) {
        stopReason = logged.finalStopReason;
        break;
      }
    }
    WorkerPipelineLog.info(
      WorkerPipelineLog.exec,
      completion.finalLog(stagesUsed),
    );
    return GemmaStagePiece(
      text: accumulated,
      stopReason: completion.finalStopReason,
      generatedChunks: generatedChunks,
      generatedTokens: estimator.estimate(accumulated),
      complete: completion.complete,
      truncated: completion.truncated,
      stagesUsed: stagesUsed,
    );
  }

  static void _logStage({
    required int stageIndex,
    required int stageInputTailChars,
    required int stageOutputChars,
    required int overlapRemovedChars,
    required int duplicateBlocksRemoved,
    required bool previousEndedIncomplete,
    required String stageStopReason,
  }) {
    WorkerPipelineLog.info(
      WorkerPipelineLog.exec,
      '[STAGE MERGE] stageIndex=$stageIndex '
      'stageInputTailChars=$stageInputTailChars '
      'stageOutputChars=$stageOutputChars '
      'overlapRemovedChars=$overlapRemovedChars '
      'duplicateBlocksRemoved=$duplicateBlocksRemoved '
      'previousEndedIncomplete=$previousEndedIncomplete '
      'stageStopReason=$stageStopReason',
    );
  }

  static String _stagePrompt({
    required int stage,
    required String original,
    required String tail,
    required LongFormSectionProgress progress,
  }) {
    final markerLine =
        'When and only when the entire requested document is truly complete, '
        'append exactly:\n${LongFormSectionPlan.marker}';
    if (stage == 0) {
      return '$original\n\n${progress.promptBlock()}\n$markerLine';
    }
    final stitched = GemmaStageMerger.continuationPrompt(original: original, tail: tail);
    return '$stitched\n\n${progress.promptBlock()}\n$markerLine';
  }

  static String continuationPrompt(String original, String soFar) {
    final incomplete = GemmaStageMerger.endedIncomplete(
      soFar,
      hitOutputLimit: true,
    );
    final tail = GemmaStageMerger.continuationTail(
      soFar,
      endedIncomplete: incomplete,
    );
    return GemmaStageMerger.continuationPrompt(original: original, tail: tail);
  }
}

class GemmaDecodePiece {
  const GemmaDecodePiece(this.text, {this.answer = true});

  final String text;
  final bool answer;
}

class GemmaBoundedDecode {
  const GemmaBoundedDecode({
    required this.text,
    required this.stopReason,
    required this.generatedChunks,
    required this.generatedTokens,
    required this.configuredOutputLimit,
  });

  final String text;
  final String stopReason;
  final int generatedChunks;
  final int generatedTokens;
  final int configuredOutputLimit;

  bool get hitOutputLimit => stopReason == GemmaGenerationOutputLimit.outputLimit;
}

/// Streams Gemma pieces until EOS, the configured chunk/char budget, JSON
/// completion, or a repetition loop. The chunk budget is [configuredOutputLimit],
/// not a hardcoded 256.
class GemmaChunkGeneration {
  static Future<GemmaBoundedDecode> collect({
    required Stream<GemmaDecodePiece> pieces,
    required int configuredOutputLimit,
    required Future<void> Function() onStop,
    TokenEstimator estimator = const TokenEstimator(),
    bool Function()? shouldContinue,
  }) async {
    final maxOutputChars =
        (configuredOutputLimit * estimator.charactersPerToken).floor();
    final boundary = JsonObjectBoundaryScanner();
    final repetition = OutputRepetitionGuard();
    final buffer = StringBuffer();
    var provisional = 'model_eos';
    var stopRequested = false;
    var generatedChunks = 0;

    await for (final piece in pieces) {
      if (stopRequested) {
        continue;
      }
      if (shouldContinue?.call() == false) {
        provisional = GemmaGenerationOutputLimit.cancelled;
        stopRequested = true;
        await onStop();
        break;
      }
      generatedChunks += 1;
      buffer.write(piece.text);
      final answerFragment = piece.answer ? piece.text : '';
      if (boundary.feed(answerFragment)) {
        provisional = 'json_complete';
      } else if (buffer.length >= maxOutputChars ||
          generatedChunks >= configuredOutputLimit) {
        provisional = 'output_limit';
      } else if (repetition.feed(answerFragment)) {
        provisional = 'repetition';
      } else {
        continue;
      }
      stopRequested = true;
      await onStop();
    }

    final stopReason = GemmaGenerationOutputLimit.finalizeStopReason(
      provisional: provisional,
      generatedChunks: generatedChunks,
      configuredOutputLimit: configuredOutputLimit,
    );
    final text = buffer.toString();
    return GemmaBoundedDecode(
      text: text,
      stopReason: stopReason,
      generatedChunks: generatedChunks,
      generatedTokens: estimator.estimate(text),
      configuredOutputLimit: configuredOutputLimit,
    );
  }
}
