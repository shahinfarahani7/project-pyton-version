import '../inference/llm/context_budget_manager.dart';
import '../validation/json_stream_boundary.dart';
import '../validation/output_repetition_guard.dart';

/// Output-generation cap for Gemma. This is separate from the LiteRT context
/// window (`maxTokens` / KV cache, 2048 in benchmark mode).
abstract final class GemmaGenerationOutputLimit {
  static const textDirect = 512;
  static const textDirectLongForm = 1024;

  static const eos = 'EOS';
  static const outputLimit = 'OUTPUT_LIMIT';
  static const cancelled = 'CANCELLED';
  static const error = 'ERROR';

  /// Retired catalog default injected into every dev manifest. It is not a
  /// caller override; text.direct must not fall back to it after resolution.
  static const legacyCatalogCap = 256;

  static GemmaOutputLimitDecision resolveTextDirect({
    required String prompt,
    int? explicitMaxOutputTokens,
    bool maxOutputTokensSpecified = false,
    bool longForm = false,
  }) {
    final detectedLongForm = longForm || requestsLongForm(prompt);
    final requested = detectedLongForm ? textDirectLongForm : textDirect;
    final specified = maxOutputTokensSpecified &&
        explicitMaxOutputTokens != null &&
        explicitMaxOutputTokens > 0 &&
        explicitMaxOutputTokens != legacyCatalogCap;
    if (specified) {
      return GemmaOutputLimitDecision(
        detectedLongForm: detectedLongForm,
        requestedOutputLimit: requested,
        effectiveOutputLimit: explicitMaxOutputTokens,
        source: 'explicit',
      );
    }
    return GemmaOutputLimitDecision(
      detectedLongForm: detectedLongForm,
      requestedOutputLimit: requested,
      effectiveOutputLimit: requested,
      source: detectedLongForm ? 'long-form' : 'default',
    );
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
    required this.detectedLongForm,
    required this.requestedOutputLimit,
    required this.effectiveOutputLimit,
    required this.source,
  });

  final bool detectedLongForm;
  final int requestedOutputLimit;
  final int effectiveOutputLimit;

  /// `explicit`, `long-form`, or `default`.
  final String source;

  String get logLine =>
      '[OUTPUT LIMIT] detectedLongForm=$detectedLongForm '
      'requestedOutputLimit=$requestedOutputLimit '
      'effectiveOutputLimit=$effectiveOutputLimit '
      'source=$source';
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
