import 'dart:convert';

import 'package:edgemint_worker/inference/llm/context_budget_manager.dart';
import 'package:edgemint_worker/inference/llm/formatted_prompt_builder.dart';
import 'package:edgemint_worker/inference/llm/output_limit_enforcer.dart';
import 'package:edgemint_worker/inference/llm/prompt_templates.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/models/worker_model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Formatted prompt boundary (T10)', () {
    const manager = ContextBudgetManager();

    test('artifact context limit is bound to ekv1280 model artifact', () {
      expect(
        ContextBudgetProfile.qwenBaseline.verifiedArtifactContextLimit,
        WorkerModelCatalog.verifiedArtifactContextLimit,
      );
      expect(WorkerModelCatalog.verifiedArtifactContextLimit, 1280);
    });

    test('effective limit is min of artifact, runtime and task policy', () {
      expect(
        manager.effectiveContextLimit(taskPolicyContextLimit: 1500),
        1280,
      );
      expect(
        manager.effectiveContextLimit(taskPolicyContextLimit: 900),
        900,
      );
    });

    test('english JSON template fits direct inference', () {
      final formatted = PromptTemplates.textClassify(
        inputText: 'Invoice total EUR 42.50',
        allowedLabelsJson: '["invoice","receipt"]',
      );
      final evaluation = manager.evaluateFormattedPrompt(
        formattedPrompt: formatted,
        maxOutputTokens: 300,
      );
      expect(evaluation.fitsDirectInference, isTrue);
    });

    test('persian OCR template near boundary uses formatted count', () {
      final ocrText = 'فاکتور فروش ${'شماره ۱۲۳۴۵ ' * 120}';
      final formatted = PromptTemplates.documentExtract(
        ocrText: ocrText,
        ocrConfidence: 0.88,
        outputSchemaJson: '{"amount":"string","date":"string"}',
      );
      final evaluation = manager.evaluateFormattedPrompt(
        formattedPrompt: formatted,
        maxOutputTokens: 300,
      );
      expect(evaluation.requiresChunkPipeline, isTrue);
      expect(evaluation.formattedPromptTokens, greaterThan(600));
    });

    test('mixed multilingual and JSON payload respects total budget', () {
      final formatted = FormattedPromptBuilder.buildContractedTask(
        taskType: 'text.classify',
        instruction: 'Classify mixed Persian/English support ticket.',
        inputJson: jsonEncode({
          'text': 'سلام hello world ${'ticket ' * 80}',
          'locale': 'fa-IR',
        }),
        outputSchemaJson: '{"label":"string","confidence":"number"}',
        systemInstruction: 'EdgeMint worker JSON-only contract.',
      );
      final evaluation = manager.evaluateFormattedPrompt(
        formattedPrompt: formatted,
        maxOutputTokens: 300,
      );
      expect(
        evaluation.totalRequiredTokens,
        evaluation.formattedPromptTokens +
            evaluation.maxOutputTokens +
            evaluation.safetyTokens,
      );
    });

    test('long system instruction consumes shared budget', () {
      final formatted = FormattedPromptBuilder.buildTaskPrompt(
        systemInstruction: 'RULE ${'x' * 900}',
        templateBody: 'tiny payload',
      );
      final evaluation = manager.evaluateFormattedPrompt(
        formattedPrompt: formatted,
        maxOutputTokens: 300,
      );
      expect(evaluation.requiresChunkPipeline, isTrue);
    });

    test('special tokens and separators are counted in formatted prompt', () {
      final formatted = '''
SYSTEM
---
payload with /no_think marker and <special> tokens
---
/no_think
''';
      final shortEval = manager.evaluateFormattedPrompt(
        formattedPrompt: formatted,
        maxOutputTokens: 300,
      );
      final longEval = manager.evaluateFormattedPrompt(
        formattedPrompt: '$formatted\n${'extra ' * 500}',
        maxOutputTokens: 300,
      );
      expect(longEval.formattedPromptTokens, greaterThan(shortEval.formattedPromptTokens));
    });
  });

  group('Output limit enforcement', () {
    const enforcer = OutputLimitEnforcer();

    test('truncated JSON output is not treated as success', () {
      final evaluation = enforcer.evaluate(
        rawOutput: '{"summary":"${'x' * 2000}"}',
        maxOutputTokens: 40,
        jsonRequired: true,
      );
      expect(evaluation.treatAsSuccess, isFalse);
      expect(evaluation.reason, OutputTerminationReason.truncatedByLimit);
    });

    test('QwenTaskProcessor rejects oversized formatted prompt before runner', () async {
      var runnerCalls = 0;
      final processor = QwenTaskProcessor(
        runner: (prompt) async {
          runnerCalls += 1;
          return prompt;
        },
      );
      final oversized = List.filled(500, 'token ').join();
      await expectLater(
        processor.runJsonTask(
          prompt: oversized,
          signingKey: 'test-signing-key',
        ),
        throwsA(isA<ContextBudgetRequiresChunkException>()),
      );
      expect(runnerCalls, 0);
    });
  });
}
