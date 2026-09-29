import '../contracts/worker_error.dart';

/// LiteRT-LM vision is configured at [Engine.create] (`max_num_images`, vision backend).
/// There is no supported post-hoc `TryLoadingVisionExecutor()` on the FFI path yet.
abstract final class GemmaLitertMultimodalVisionPolicy {
  static const textOnlyMaxNumImages = 0;
  static const multimodalMaxNumImages = 1;

  static bool shouldReloadEngineForVision({
    required bool visionExecutorLoaded,
    required bool multimodalTask,
  }) =>
      multimodalTask && !visionExecutorLoaded;

  static String visionRuntimeLogLine({
    required bool visionExecutorLoaded,
    required bool multimodal,
  }) {
    final maxNumImages =
        multimodal && visionExecutorLoaded
            ? multimodalMaxNumImages
            : textOnlyMaxNumImages;
    return '[VISION RUNTIME] visionExecutorLoaded=$visionExecutorLoaded '
        'maxNumImages=$maxNumImages multimodal=$multimodal';
  }

  static WorkerError visionRuntimeNotReady(String detail) {
    return WorkerError(
      code: WorkerErrorCode.visionRuntimeNotReady,
      message: detail,
      retryable: true,
      stage: WorkerTaskStage.llm,
    );
  }

  static WorkerError? classifyInferenceFailure(Object error) {
    if (error is WorkerError) {
      return error;
    }
    final text = error.toString();
    if (_isVisionExecutorFailure(text)) {
      return visionRuntimeNotReady(text);
    }
    return null;
  }

  static bool _isVisionExecutorFailure(String text) {
    final lower = text.toLowerCase();
    return lower.contains('vision executor') ||
        lower.contains('tryloadingvisionexecutor') ||
        lower.contains('max_num_images: 0');
  }
}
