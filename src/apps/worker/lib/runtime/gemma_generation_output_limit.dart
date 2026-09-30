import '../inference/llm/context_budget_manager.dart';
import '../validation/json_stream_boundary.dart';
import '../validation/output_repetition_guard.dart';
import 'gemma_stage_merger.dart';
import 'worker_pipeline_log.dart';

/// Output-generation cap for Gemma. This is separate from the LiteRT context
/// window (`maxTokens` / KV cache, 2048 in benchmark mode).
abstract final class GemmaGenerationOutputLimit {
  /// Short/default free-form answer. Also the per-stage cap for long-form.
  static const textDirectShort = 256;

  /// Medium answer: explain, elaborate, or a normally detailed reply.
  static const textDirectMedium = 384;

  /// Explicitly detailed or extended answer, still one session.
  static const textDirectDetailed = 512;

  /// Kept as the short/default cap. Not the long-form session size.
  static const textDirect = textDirectShort;

  static const longFormMaxStages = 6;
  static const longFormHardMaxStages = 8;

  static const eos = 'EOS';
  static const outputLimit = 'OUTPUT_LIMIT';
  static const longFormStageLimit = 'LONG_FORM_STAGE_LIMIT';
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
  }) {
    final eos = stopReason == GemmaGenerationOutputLimit.eos || stopReason == 'model_eos';
    final hitLimit = stopReason == GemmaGenerationOutputLimit.outputLimit ||
        stopReason == 'output_limit';
    final endedIncomplete = !eos && textIsIncomplete(text);
    final shouldContinue = hitLimit && endedIncomplete && stagesUsed < hardMaxStages;
    final complete = !endedIncomplete;
    final truncated = endedIncomplete && !shouldContinue;
    return LongFormCompletionDecision(
      endedIncomplete: endedIncomplete,
      shouldContinue: shouldContinue,
      complete: complete,
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
  }) async {
    if (!decision.staged) {
      return generateStage(0, prompt);
    }

    final stageBudget = maxStages ?? GemmaGenerationOutputLimit.longFormMaxStages;
    final hardBudget = hardMaxStages ?? GemmaGenerationOutputLimit.longFormHardMaxStages;
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
    for (var stage = 0; stage < safetyLimit; stage++) {
      final previousEndedIncomplete = stage > 0 &&
          LongFormCompletion.textIsIncomplete(accumulated);
      final tail = stage == 0
          ? ''
          : GemmaStageMerger.continuationTail(
              accumulated,
              endedIncomplete: previousEndedIncomplete,
            );
      final stagePrompt = stage == 0
          ? prompt
          : GemmaStageMerger.continuationPrompt(original: prompt, tail: tail);
      final piece = await generateStage(stage, stagePrompt);
      generatedChunks += piece.generatedChunks;
      stopReason = piece.stopReason;
      stagesUsed = stage + 1;
      if (piece.text.trim().isEmpty) {
        _logStage(
          stageIndex: stage,
          stageInputTailChars: tail.length,
          stageOutputChars: piece.text.length,
          overlapRemovedChars: 0,
          duplicateBlocksRemoved: 0,
          previousEndedIncomplete: previousEndedIncomplete,
          stageStopReason: piece.stopReason,
        );
        completion = LongFormCompletion.evaluate(
          text: accumulated,
          stopReason: piece.stopReason,
          stagesUsed: stagesUsed,
          maxStages: stageBudget,
          hardMaxStages: safetyLimit,
        );
        WorkerPipelineLog.info(WorkerPipelineLog.exec, completion.logLine(stage, piece.stopReason));
        break;
      }
      final merge = stage == 0
          ? GemmaStageMerge(
              text: piece.text.trimRight(),
              overlapRemovedChars: 0,
              duplicateBlocksRemoved: 0,
            )
          : GemmaStageMerger.merge(
              previousText: accumulated,
              nextText: piece.text,
              previousEndedIncomplete: previousEndedIncomplete,
            );
      _logStage(
        stageIndex: stage,
        stageInputTailChars: tail.length,
        stageOutputChars: piece.text.length,
        overlapRemovedChars: merge.overlapRemovedChars,
        duplicateBlocksRemoved: merge.duplicateBlocksRemoved,
        previousEndedIncomplete: previousEndedIncomplete,
        stageStopReason: piece.stopReason,
      );
      final madeProgress = stage == 0 || merge.text != accumulated;
      accumulated = merge.text;
      completion = LongFormCompletion.evaluate(
        text: accumulated,
        stopReason: piece.stopReason,
        stagesUsed: stagesUsed,
        maxStages: stageBudget,
        hardMaxStages: safetyLimit,
      );
      final shouldContinue = completion.shouldContinue && madeProgress;
      final logged = LongFormCompletionDecision(
        endedIncomplete: completion.endedIncomplete,
        shouldContinue: shouldContinue,
        complete: completion.complete,
        truncated: completion.endedIncomplete && !shouldContinue,
        finalStopReason: completion.endedIncomplete && !shouldContinue
            ? GemmaGenerationOutputLimit.longFormStageLimit
            : piece.stopReason,
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
