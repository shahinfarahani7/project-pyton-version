import '../../models/worker_model_catalog.dart';
import 'formatted_prompt_builder.dart';

/// Conservative Qwen baseline context budget (Architecture Section 25).
class ContextBudgetProfile {
  const ContextBudgetProfile({
    required this.totalContextTokens,
    required this.systemTemplateTokens,
    required this.inputBudgetTokens,
    required this.outputReserveTokens,
    required this.safetyMarginTokens,
    required this.verifiedArtifactContextLimit,
    required this.configuredRuntimeContextLimit,
  });

  static const int qwenBaselineTotalContextTokens = 4096;
  static const int qwenBaselineOutputReserveTokens = 512;
  final int totalContextTokens;
  final int systemTemplateTokens;
  final int inputBudgetTokens;
  final int outputReserveTokens;
  final int safetyMarginTokens;
  final int verifiedArtifactContextLimit;
  final int configuredRuntimeContextLimit;

  /// Active on-device LLM context budget (currently Gemma 4 E4B).
 static const ContextBudgetProfile qwenBaseline = ContextBudgetProfile(
   totalContextTokens: qwenBaselineTotalContextTokens,
   systemTemplateTokens: 96,
   inputBudgetTokens: 3456,
   outputReserveTokens: qwenBaselineOutputReserveTokens,
   safetyMarginTokens: 32,
   verifiedArtifactContextLimit: WorkerModelCatalog.verifiedArtifactContextLimit,
   configuredRuntimeContextLimit: WorkerModelCatalog.runtimeMaxTokens,
 );
}
/// Deterministic token estimate before native runtime (Architecture Section 25).
class TokenEstimator {
  const TokenEstimator({this.charactersPerToken = 3.5});

  final double charactersPerToken;

  int estimate(String text) {
    if (text.isEmpty) {
      return 0;
    }
    return (text.length / charactersPerToken).ceil();
  }
}

enum ContextExecutionRoute { directInference, chunkPipeline }

class FormattedPromptEvaluation {
  const FormattedPromptEvaluation({
    required this.route,
    required this.formattedPromptTokens,
    required this.effectiveContextLimit,
    required this.maxOutputTokens,
    required this.safetyTokens,
    required this.totalRequiredTokens,
  });

  final ContextExecutionRoute route;
  final int formattedPromptTokens;
  final int effectiveContextLimit;
  final int maxOutputTokens;
  final int safetyTokens;
  final int totalRequiredTokens;

  bool get requiresChunkPipeline => route == ContextExecutionRoute.chunkPipeline;
  bool get fitsDirectInference => !requiresChunkPipeline;
}

class ContextBudgetEvaluation {
  const ContextBudgetEvaluation({
    required this.route,
    required this.estimatedPromptTokens,
    required this.estimatedSystemTokens,
    required this.estimatedTotalTokens,
    required this.inputBudgetTokens,
  });

  final ContextExecutionRoute route;
  final int estimatedPromptTokens;
  final int estimatedSystemTokens;
  final int estimatedTotalTokens;
  final int inputBudgetTokens;

  bool get requiresChunkPipeline => route == ContextExecutionRoute.chunkPipeline;
}

/// Guards prompt size before LiteRT/Qwen native runtime invocation.
class ContextBudgetManager {
  const ContextBudgetManager({
    this.profile = ContextBudgetProfile.qwenBaseline,
    this.estimator = const TokenEstimator(),
    this.defaultSystemInstruction =
        'You are EdgeMint worker AI. Answer concisely for the assigned task payload.',
  });

  final ContextBudgetProfile profile;
  final TokenEstimator estimator;
  final String defaultSystemInstruction;

  int effectiveContextLimit({int? taskPolicyContextLimit}) {
    final taskLimit = taskPolicyContextLimit ?? profile.totalContextTokens;
    return [
      profile.verifiedArtifactContextLimit,
      profile.configuredRuntimeContextLimit,
      taskLimit,
    ].reduce((left, right) => left < right ? left : right);
  }

  int capMaxOutputTokens(int requested) =>
      requested.clamp(1, profile.outputReserveTokens);

  FormattedPromptEvaluation evaluateFormattedPrompt({
    required String formattedPrompt,
    required int maxOutputTokens,
    int? taskPolicyContextLimit,
  }) {
    final promptTokens = estimator.estimate(formattedPrompt);
    final safetyTokens = profile.safetyMarginTokens;
    final effectiveLimit = effectiveContextLimit(
      taskPolicyContextLimit: taskPolicyContextLimit,
    );
    final cappedOutput = capMaxOutputTokens(maxOutputTokens);
    final totalRequired = promptTokens + cappedOutput + safetyTokens;
    final exceedsInput = promptTokens > profile.inputBudgetTokens;
    final exceedsTotal = totalRequired > effectiveLimit;
    final route = exceedsInput || exceedsTotal
        ? ContextExecutionRoute.chunkPipeline
        : ContextExecutionRoute.directInference;

    return FormattedPromptEvaluation(
      route: route,
      formattedPromptTokens: promptTokens,
      effectiveContextLimit: effectiveLimit,
      maxOutputTokens: cappedOutput,
      safetyTokens: safetyTokens,
      totalRequiredTokens: totalRequired,
    );
  }

  ContextBudgetEvaluation evaluate({
    required String prompt,
    String? systemInstruction,
  }) {
    final formatted = FormattedPromptBuilder.buildTaskPrompt(
      templateBody: prompt,
      systemInstruction: systemInstruction ?? defaultSystemInstruction,
    );
    final evaluation = evaluateFormattedPrompt(
      formattedPrompt: formatted,
      maxOutputTokens: profile.outputReserveTokens,
    );
    final systemTokens = estimator.estimate(systemInstruction ?? defaultSystemInstruction);
    final promptTokens = estimator.estimate(prompt);
    return ContextBudgetEvaluation(
      route: evaluation.route,
      estimatedPromptTokens: promptTokens,
      estimatedSystemTokens: systemTokens,
      estimatedTotalTokens: evaluation.totalRequiredTokens,
      inputBudgetTokens: profile.inputBudgetTokens,
    );
  }

  void ensureDirectInferenceOrThrow({
    required String prompt,
    String? systemInstruction,
    int? maxOutputTokens,
  }) {
    final formatted = FormattedPromptBuilder.buildTaskPrompt(
      templateBody: prompt,
      systemInstruction: systemInstruction ?? defaultSystemInstruction,
    );
    final evaluation = evaluateFormattedPrompt(
      formattedPrompt: formatted,
      maxOutputTokens: maxOutputTokens ?? profile.outputReserveTokens,
    );
    if (evaluation.requiresChunkPipeline) {
      throw ContextBudgetRequiresChunkException(
        ContextBudgetEvaluation(
          route: evaluation.route,
          estimatedPromptTokens: evaluation.formattedPromptTokens,
          estimatedSystemTokens: 0,
          estimatedTotalTokens: evaluation.totalRequiredTokens,
          inputBudgetTokens: profile.inputBudgetTokens,
        ),
      );
    }
  }
}

/// Raised before native runtime when input must use the chunk pipeline (P3-T06+).
class ContextBudgetRequiresChunkException implements Exception {
  ContextBudgetRequiresChunkException(this.evaluation);

  final ContextBudgetEvaluation evaluation;

  @override
  String toString() =>
      'ContextBudgetRequiresChunkException('
      'promptTokens=${evaluation.estimatedPromptTokens}, '
      'budget=${evaluation.inputBudgetTokens})';
}
