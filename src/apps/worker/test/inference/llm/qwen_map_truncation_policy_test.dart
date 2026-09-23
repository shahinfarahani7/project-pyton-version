import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:flutter_test/flutter_test.dart';

/// NOT RUN — prepared for manual/CI execution by the developer.
void main() {
  group('Map truncation corrective policy', () {
    late QwenTaskProcessor processor;

    setUp(() {
      processor = QwenTaskProcessor();
    });

    test('labeled fallback is disabled on map stage', () {
      expect(
        processor.labeledFallbackEnabled(
          sourcePrompt: 'Chunk metadata: chunkIndex=0',
          mapStage: true,
        ),
        isFalse,
      );
    });

    test('labeled fallback stays enabled off map stage', () {
      expect(
        processor.labeledFallbackEnabled(
          sourcePrompt: 'Summarize this text',
          mapStage: false,
        ),
        isTrue,
      );
    });
  });
}
