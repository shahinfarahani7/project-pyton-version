import 'dart:convert';

import 'context_budget_manager.dart';
import 'formatted_prompt_builder.dart';
import 'prompt_templates.dart';
import 'summarize_task_constraints.dart';

/// Evaluates reduce prompts using the actual encoded map partials.
abstract final class SummarizeReduceBudget {
  static FormattedPromptEvaluation evaluate({
    required ContextBudgetManager contextBudget,
    required List<Map<String, dynamic>> partials,
    required String? userInstructions,
    SummarizeTaskConstraintsV1? constraints,
    required int maxOutputTokens,
  }) {
    final partialsJson = jsonEncode(partials);
    final prompt = PromptTemplates.summarizeReduce(
      partialSummariesJson: partialsJson,
      chunkCount: partials.length,
      userInstructions: userInstructions,
      constraints: constraints,
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
