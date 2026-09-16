import 'package:edgemint_worker/inference/llm/context_budget_manager.dart';

/// Repeats [unit] until the estimate clears the profile input budget, so the
/// fixture stays oversized when the budget is re-tuned.
String oversizedFiller({
  String unit = 'token ',
  ContextBudgetProfile profile = ContextBudgetProfile.qwenBaseline,
  TokenEstimator estimator = const TokenEstimator(),
  int marginTokens = 80,
}) {
  final targetTokens = profile.inputBudgetTokens + marginTokens;
  final repeats = (targetTokens * estimator.charactersPerToken / unit.length)
      .ceil();
  return unit * repeats;
}
