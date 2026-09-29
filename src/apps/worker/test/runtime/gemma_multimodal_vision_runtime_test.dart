import 'package:edgemint_worker/contracts/worker_error.dart';
import 'package:edgemint_worker/runtime/gemma_multimodal_vision_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GemmaLitertMultimodalVisionPolicy', () {
    test('text-only task does not require engine reload', () {
      expect(
        GemmaLitertMultimodalVisionPolicy.shouldReloadEngineForVision(
          visionExecutorLoaded: false,
          multimodalTask: false,
        ),
        isFalse,
      );
      expect(
        GemmaLitertMultimodalVisionPolicy.visionRuntimeLogLine(
          visionExecutorLoaded: false,
          multimodal: false,
        ),
        contains('maxNumImages=0'),
      );
      expect(
        GemmaLitertMultimodalVisionPolicy.visionRuntimeLogLine(
          visionExecutorLoaded: false,
          multimodal: false,
        ),
        contains('multimodal=false'),
      );
    });

    test('valid image task requires vision engine when not yet loaded', () {
      expect(
        GemmaLitertMultimodalVisionPolicy.shouldReloadEngineForVision(
          visionExecutorLoaded: false,
          multimodalTask: true,
        ),
        isTrue,
      );
      expect(
        GemmaLitertMultimodalVisionPolicy.visionRuntimeLogLine(
          visionExecutorLoaded: true,
          multimodal: true,
        ),
        contains('visionExecutorLoaded=true'),
      );
      expect(
        GemmaLitertMultimodalVisionPolicy.visionRuntimeLogLine(
          visionExecutorLoaded: true,
          multimodal: true,
        ),
        contains('maxNumImages=1'),
      );
    });

    test('classifies native vision executor failures', () {
      const nativeMessage =
          'INVALID_ARGUMENT: Vision executor should not be null, '
          'please TryLoadingVisionExecutor() first.';
      final error = GemmaLitertMultimodalVisionPolicy.classifyInferenceFailure(
        Exception(nativeMessage),
      );
      expect(error, isNotNull);
      expect(error!.code, WorkerErrorCode.visionRuntimeNotReady);
      expect(error.codeName, 'VISION_RUNTIME_NOT_READY');
      expect(error.retryable, isTrue);
    });

    test('vision executor initialization failure helper', () {
      final error = GemmaLitertMultimodalVisionPolicy.visionRuntimeNotReady(
        'engine reload blocked',
      );
      expect(error.code, WorkerErrorCode.visionRuntimeNotReady);
      expect(error.stage, WorkerTaskStage.llm);
    });
  });
}
