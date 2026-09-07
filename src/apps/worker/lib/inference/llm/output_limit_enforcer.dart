import 'context_budget_manager.dart';

enum OutputTerminationReason {
  complete,
  truncatedByLimit,
  invalidOutput,
}

class OutputLimitEvaluation {
  const OutputLimitEvaluation({
    required this.estimatedOutputTokens,
    required this.maxOutputTokens,
    required this.reason,
    required this.treatAsSuccess,
  });

  final int estimatedOutputTokens;
  final int maxOutputTokens;
  final OutputTerminationReason reason;
  final bool treatAsSuccess;
}

/// Enforces certified output token limits; truncated JSON is not silent success.
class OutputLimitEnforcer {
  const OutputLimitEnforcer({
    this.estimator = const TokenEstimator(),
  });

  final TokenEstimator estimator;

  OutputLimitEvaluation evaluate({
    required String rawOutput,
    required int maxOutputTokens,
    bool jsonRequired = true,
  }) {
    final estimated = estimator.estimate(rawOutput);
    if (estimated > maxOutputTokens) {
      return OutputLimitEvaluation(
        estimatedOutputTokens: estimated,
        maxOutputTokens: maxOutputTokens,
        reason: OutputTerminationReason.truncatedByLimit,
        treatAsSuccess: false,
      );
    }
    final trimmed = rawOutput.trim();
    if (jsonRequired && trimmed.isNotEmpty && !trimmed.startsWith('{')) {
      return OutputLimitEvaluation(
        estimatedOutputTokens: estimated,
        maxOutputTokens: maxOutputTokens,
        reason: OutputTerminationReason.invalidOutput,
        treatAsSuccess: false,
      );
    }
    return OutputLimitEvaluation(
      estimatedOutputTokens: estimated,
      maxOutputTokens: maxOutputTokens,
      reason: OutputTerminationReason.complete,
      treatAsSuccess: true,
    );
  }
}

class OutputLimitExceededException implements Exception {
  OutputLimitExceededException(this.evaluation);

  final OutputLimitEvaluation evaluation;

  @override
  String toString() =>
      'OutputLimitExceededException(reason=${evaluation.reason.name}, '
      'estimated=${evaluation.estimatedOutputTokens}, '
      'max=${evaluation.maxOutputTokens})';
}
