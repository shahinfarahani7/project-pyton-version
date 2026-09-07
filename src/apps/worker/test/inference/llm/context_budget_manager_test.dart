import 'package:edgemint_worker/inference/llm/context_budget_manager.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Oversized fixture: ~2500 chars ≈ 715 estimated tokens (> 600 input budget).
String oversizedPromptFixture() => List.filled(500, 'token ').join();

void main() {
  group('ContextBudgetManager', () {
    const manager = ContextBudgetManager();

    test('nominal prompt routes to direct inference', () {
      final evaluation = manager.evaluate(prompt: 'Summarize this short paragraph.');
      expect(evaluation.route, ContextExecutionRoute.directInference);
      expect(evaluation.requiresChunkPipeline, isFalse);
      expect(evaluation.estimatedPromptTokens, lessThan(600));
    });

    test('oversized prompt fixture routes to chunk pipeline', () {
      final prompt = oversizedPromptFixture();
      final evaluation = manager.evaluate(prompt: prompt);

      expect(evaluation.route, ContextExecutionRoute.chunkPipeline);
      expect(evaluation.requiresChunkPipeline, isTrue);
      expect(evaluation.estimatedPromptTokens, greaterThan(600));
    });

    test('ensureDirectInferenceOrThrow blocks native path for oversized input', () {
      expect(
        () => manager.ensureDirectInferenceOrThrow(prompt: oversizedPromptFixture()),
        throwsA(isA<ContextBudgetRequiresChunkException>()),
      );
    });
  });

  group('QwenTaskProcessor', () {
    test('does not invoke runner when context budget requires chunk pipeline', () async {
      var runnerCalls = 0;
      final processor = QwenTaskProcessor(
        runner: (prompt) async {
          runnerCalls += 1;
          return prompt;
        },
      );

      await expectLater(
        processor.runJsonTask(
          prompt: oversizedPromptFixture(),
          signingKey: 'test-signing-key',
        ),
        throwsA(isA<ContextBudgetRequiresChunkException>()),
      );
      expect(runnerCalls, 0);
    });
  });
}
