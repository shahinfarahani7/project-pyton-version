import 'context_budget_manager.dart';
import 'formatted_prompt_builder.dart';
import 'prompt_templates.dart';
import 'reduce_partial_envelope.dart';
import 'summarize_task_constraints.dart';

/// Evaluates reduce prompts using the actual encoded map partial envelopes.
abstract final class SummarizeReduceBudget {
  static FormattedPromptEvaluation evaluate({
    required ContextBudgetManager contextBudget,
    required List<ReducePartialEnvelope> envelopes,
    required String? userInstructions,
    SummarizeTaskConstraintsV1? constraints,
    required int maxOutputTokens,
    required bool isFinalMerge,
    bool factsOnly = false,
  }) {
    final partialsJson = ReducePartialEnvelope.encodeForPrompt(envelopes);
    final prompt = isFinalMerge
        ? PromptTemplates.summarizeReduceFinal(
            partialSummariesJson: partialsJson,
            chunkCount: envelopes.length,
            userInstructions: userInstructions,
            constraints: constraints,
            factsOnly: factsOnly,
          )
        : PromptTemplates.summarizeReduceIntermediate(
            partialSummariesJson: partialsJson,
            chunkCount: envelopes.length,
            userInstructions: userInstructions,
            constraints: constraints,
            factsOnly: factsOnly,
          );
    final formatted = FormattedPromptBuilder.buildTaskPrompt(
      templateBody: prompt,
      systemInstruction: contextBudget.defaultSystemInstruction,
    );
    return contextBudget.evaluateFormattedPrompt(
      formattedPrompt: formatted,
      maxOutputTokens: maxOutputTokens,
    );
  }
}
