import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/llm/summarize_inference_stage.dart';
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
          policy: SummarizeStagePolicy.forStage(
            SummarizeInferenceStage.mapEvidence,
          ),
        ),
        isFalse,
      );
    });

    test('labeled fallback stays enabled off map stage', () {
      expect(
        processor.labeledFallbackEnabled(
          sourcePrompt: 'Summarize this text',
          policy: SummarizeStagePolicy.forStage(
            SummarizeInferenceStage.directPublic,
          ),
        ),
        isTrue,
      );
    });
  });
}
