import 'package:edgemint_worker/contracts/worker_task_request.dart';
import 'package:edgemint_worker/inference/llm/direct_answer_instruction.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/ocr/fake_ocr_engine.dart';
import 'package:edgemint_worker/runtime/gemma_inference_adapter.dart';
import 'package:edgemint_worker/tasks/handlers/direct_prompt_handler.dart';
import 'package:edgemint_worker/telemetry/worker_task_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('portal answer forbids a question back to the user', () async {
    final adapter = GemmaLiteRtInferenceAdapter();
    String? seen;
    final processor = QwenTaskProcessor(
      adapter: adapter,
      runner: (prompt) async {
        seen = prompt;
        expect(adapter.usePortalPassthroughChat, isTrue);
        expect(
          adapter.portalSessionSystemInstruction,
          DirectAnswerInstruction.system,
        );
        expect(
          GemmaLiteRtInferenceAdapter.resolveChatSystemInstruction(
            portalPassthrough: adapter.usePortalPassthroughChat,
            portalSessionSystemInstruction:
                adapter.portalSessionSystemInstruction,
          ),
          DirectAnswerInstruction.system.trim(),
        );
        return 'قیمت طلا امروز بالا است.\n\nآیا سؤال دیگری دارید؟';
      },
    );

    final result = await DirectPromptHandler().handle(
      request: const WorkerTaskRequest(
        schemaVersion: '1.0',
        taskId: 'tsk-direct',
        idempotencyKey: 'idem',
        type: 'text.direct.v1',
        input: WorkerTaskInput(text: 'قیمت طلا چقدر است'),
      ),
      ocrEngine: FakeOcrEngine(),
      qwenProcessor: processor,
      signingKey: 'sign',
      metrics: WorkerTaskMetrics(),
    );

    expect(seen, contains('Do not ask the user any question'));
    expect(seen, contains('قیمت طلا چقدر است'));
    expect(seen, contains(DirectAnswerInstruction.userTurnMarker));
    expect(seen, isNot(contains('assigned task payload')));
    expect(result.output?['rawText'], 'قیمت طلا امروز بالا است.');
    expect(result.output?['modelTranscript'], 'قیمت طلا امروز بالا است.');
    expect(adapter.usePortalPassthroughChat, isFalse);
    expect(adapter.portalSessionSystemInstruction, isNull);
  });

  test(
    'OCR transcription stays a raw prompt without the one-shot rule',
    () async {
      final adapter = GemmaLiteRtInferenceAdapter();
      final processor = QwenTaskProcessor(
        adapter: adapter,
        runner: (prompt) async {
          expect(
            prompt,
            isNot(contains(DirectAnswerInstruction.userTurnMarker)),
          );
          expect(prompt, isNot(contains('This chat cannot continue')));
          expect(adapter.usePortalPassthroughChat, isTrue);
          expect(adapter.portalSessionSystemInstruction, isNull);
          expect(
            GemmaLiteRtInferenceAdapter.resolveChatSystemInstruction(
              portalPassthrough: true,
              portalSessionSystemInstruction:
                  adapter.portalSessionSystemInstruction,
            ),
            isNull,
          );
          return 'Line one';
        },
      );

      final text = await processor.runDirectUserText(
        'Transcribe every line of visible text in this image.',
        signingKey: 'sign',
      );

      expect(text, 'Line one');
    },
  );

  test(
    'chat system instruction keeps the worker default off the portal path',
    () {
      expect(
        GemmaLiteRtInferenceAdapter.resolveChatSystemInstruction(
          portalPassthrough: false,
        ),
        GemmaLiteRtInferenceAdapter.defaultSystemInstruction,
      );
      expect(
        GemmaLiteRtInferenceAdapter.resolveChatSystemInstruction(
          portalPassthrough: true,
        ),
        isNull,
      );
      expect(
        GemmaLiteRtInferenceAdapter.resolveChatSystemInstruction(
          portalPassthrough: true,
          portalSessionSystemInstruction: DirectAnswerInstruction.system,
        ),
        DirectAnswerInstruction.system.trim(),
      );
    },
  );

  test('trailing invitations are removed and requested questions stay', () {
    expect(
      DirectAnswerInstruction.stripTrailingInvitation(
        'قیمت طلا امروز بالا است. Would you like me to explain more?',
      ),
      'قیمت طلا امروز بالا است.',
    );
    expect(
      DirectAnswerInstruction.stripTrailingInvitation(
        'اگر خواستید ادامه بدهم بگویید.',
      ),
      'اگر خواستید ادامه بدهم بگویید.',
    );
    expect(
      DirectAnswerInstruction.stripTrailingInvitation(
        '1. What is a closure?\n2. What is a future?',
      ),
      '1. What is a closure?\n2. What is a future?',
    );
    expect(
      DirectAnswerInstruction.attach(DirectAnswerInstruction.attach('سلام')),
      DirectAnswerInstruction.attach('سلام'),
    );
  });
}
