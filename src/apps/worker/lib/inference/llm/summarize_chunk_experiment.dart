import '../../contracts/worker_error.dart';
import 'summarize_evidence_pipeline.dart';

/// Opt-in Phase 2 source-chunk token cap experiment (compile-time only).
abstract final class SummarizeChunkExperiment {
  static const _rawRequestedSourceChunkTokens = String.fromEnvironment(
    'SUMMARIZE_EXPERIMENT_SOURCE_CHUNK_TOKENS',
    defaultValue: '',
  );

  static const tokenEstimatorLabel = 'TokenEstimator.charactersPerToken=3.5';

  static const configurationName = 'SUMMARIZE_EXPERIMENT_SOURCE_CHUNK_TOKENS';

  static int get requestedSourceChunkTokens =>
      parseRequestedSourceChunkTokens(
        _rawRequestedSourceChunkTokens,
        throwOnInvalid: false,
      );

  static bool get compileTimeRequested {
    final raw = _rawRequestedSourceChunkTokens.trim();
    return raw.isNotEmpty && raw != '0';
  }

  static bool get active =>
      SummarizeEvidencePipeline.enabled && requestedSourceChunkTokens > 0;

  /// Parses the compile-time dart-define value.
  ///
  /// Empty or `0` disables the experiment. Malformed values throw
  /// [WorkerError] when [throwOnInvalid] is true; otherwise return 0.
  static int parseRequestedSourceChunkTokens(
    String raw, {
    bool throwOnInvalid = true,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == '0') {
      return 0;
    }
    final parsed = int.tryParse(trimmed);
    if (parsed == null) {
      if (throwOnInvalid) {
        throw WorkerError(
          code: WorkerErrorCode.invalidTask,
          message:
              'Invalid $configurationName="$trimmed"; '
              'must be 0 (disabled) or a positive integer',
          retryable: false,
          stage: WorkerTaskStage.validation,
        );
      }
      return 0;
    }
    if (parsed < 0) {
      if (throwOnInvalid) {
        throw WorkerError(
          code: WorkerErrorCode.invalidTask,
          message:
              'Invalid $configurationName=$parsed; '
              'must be 0 (disabled) or a positive integer',
          retryable: false,
          stage: WorkerTaskStage.validation,
        );
      }
      return 0;
    }
    return parsed;
  }

  /// Checkpoint [promptVersion] suffix when the experiment is active.
  static String checkpointPromptVersion(String basePromptVersion) {
    if (!active) {
      return basePromptVersion;
    }
    return '$basePromptVersion+srcCap$requestedSourceChunkTokens';
  }

  static String activeCheckpointPromptVersion(String basePromptVersion) =>
      checkpointPromptVersion(basePromptVersion);

  /// Validates compile-time configuration before summarize chunk planning.
  static void assertValidConfigurationOrThrow() {
    parseRequestedSourceChunkTokens(
      _rawRequestedSourceChunkTokens,
      throwOnInvalid: true,
    );
  }

  /// Resolves per-chunk Map source-body budgets (overlap included).
  ///
  /// [safeTotalSourceBodyTokenBudget] is [chunkTokenBudget] — the existing
  /// direct-inference body ceiling excluding prompt wrapper/output reserve.
  /// [preOverlapPackTokenBudget] is `(effectiveTotal - overlapTokens)` and
  /// is used only for segment packing before overlap merge.
  static SummarizeChunkExperimentBudget resolveBudget({
    required int chunkTokenBudget,
    required int overlapTokens,
  }) {
    assertValidConfigurationOrThrow();
    return resolveBudgetFromCap(
      chunkTokenBudget: chunkTokenBudget,
      overlapTokens: overlapTokens,
      requestedCap: active ? requestedSourceChunkTokens : null,
      invalidCapErrorFactory: (message) => WorkerError(
        code: WorkerErrorCode.invalidTask,
        message: message,
        retryable: false,
        stage: WorkerTaskStage.validation,
      ),
    );
  }

  /// Shared budget math for compile-time activation and engine test caps.
  static SummarizeChunkExperimentBudget resolveBudgetFromCap({
    required int chunkTokenBudget,
    required int overlapTokens,
    required int? requestedCap,
    Object Function(String message)? invalidCapErrorFactory,
  }) {
    final safeTotal = chunkTokenBudget;
    final defaultPreOverlap = (chunkTokenBudget - overlapTokens)
        .clamp(1, chunkTokenBudget)
        .toInt();

    if (requestedCap == null || requestedCap <= 0) {
      return SummarizeChunkExperimentBudget(
        requestedSourceChunkTokens: 0,
        chunkTokenBudget: chunkTokenBudget,
        overlapTokens: overlapTokens,
        safeTotalSourceBodyTokenBudget: safeTotal,
        effectiveTotalSourceBodyTokenBudget: safeTotal,
        preOverlapPackTokenBudget: defaultPreOverlap,
        active: false,
      );
    }

    if (requestedCap < overlapTokens + 1) {
      final message =
          '$configurationName=$requestedCap cannot support '
          'overlapReserveTokens=$overlapTokens plus new source content; '
          'increase the cap or disable the experiment';
      if (invalidCapErrorFactory != null) {
        throw invalidCapErrorFactory(message);
      }
      throw StateError(message);
    }

    final effectiveTotal =
        safeTotal < requestedCap ? safeTotal : requestedCap;
    final preOverlap = (effectiveTotal - overlapTokens)
        .clamp(1, effectiveTotal)
        .toInt();

    return SummarizeChunkExperimentBudget(
      requestedSourceChunkTokens: requestedCap,
      chunkTokenBudget: chunkTokenBudget,
      overlapTokens: overlapTokens,
      safeTotalSourceBodyTokenBudget: safeTotal,
      effectiveTotalSourceBodyTokenBudget: effectiveTotal,
      preOverlapPackTokenBudget: preOverlap,
      active: true,
    );
  }

  static String activationLogLine(SummarizeChunkExperimentBudget budget) =>
      '[SUMMARIZE CHUNK EXPERIMENT] '
      'enabled=${budget.active} '
      'requestedTotalBodyTokens=${budget.requestedSourceChunkTokens} '
      'safeTotalBodyTokens=${budget.safeTotalSourceBodyTokenBudget} '
      'effectiveTotalBodyTokens=${budget.effectiveTotalSourceBodyTokenBudget} '
      'preOverlapPackTokens=${budget.preOverlapPackTokenBudget} '
      'overlapReserveTokens=${budget.overlapTokens} '
      'chunkTokenBudget=${budget.chunkTokenBudget} '
      'tokenEstimator=$tokenEstimatorLabel';
}

final class SummarizeChunkExperimentBudget {
  const SummarizeChunkExperimentBudget({
    required this.requestedSourceChunkTokens,
    required this.chunkTokenBudget,
    required this.overlapTokens,
    required this.safeTotalSourceBodyTokenBudget,
    required this.effectiveTotalSourceBodyTokenBudget,
    required this.preOverlapPackTokenBudget,
    required this.active,
  });

  final int requestedSourceChunkTokens;
  final int chunkTokenBudget;
  final int overlapTokens;
  final int safeTotalSourceBodyTokenBudget;
  final int effectiveTotalSourceBodyTokenBudget;
  final int preOverlapPackTokenBudget;
  final bool active;

  int? get appliedCap => active ? requestedSourceChunkTokens : null;
}
