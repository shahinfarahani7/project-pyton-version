import '../../contracts/worker_error.dart';
import '../../contracts/worker_task_request.dart';
import '../../contracts/worker_task_result.dart';
import '../../inference/llm/qwen_task_processor.dart';
import '../../inference/ocr/ocr_engine.dart';
import '../../inference/vision/lightweight_vision.dart';
import '../../telemetry/worker_task_metrics.dart';
import 'task_handler.dart';

abstract class _VisionHandler implements TaskHandler {
  const _VisionHandler();
  LightweightVision get vision => const LightweightVision();

  WorkerTaskResult success(WorkerTaskRequest request, Map<String, dynamic> data) =>
      WorkerTaskResult(
        schemaVersion: request.schemaVersion,
        taskId: request.taskId,
        status: WorkerResultStatus.succeeded,
        output: {'data': data},
      );
}

class BlurryImageHandler extends _VisionHandler {
  @override
  String get capability => 'quality.blurry_image';

  @override
  Future<WorkerTaskResult> handle({required WorkerTaskRequest request, required OcrEngine ocrEngine, required QwenTaskProcessor qwenProcessor, required String signingKey, required WorkerTaskMetrics metrics, bool Function()? isCancelled}) async {
    final variance = vision.blurVariance(request.input.imageBytes!);
    return success(request, {'laplacianVariance': variance, 'blurry': variance < 100, 'threshold': 100});
  }
}

class DocumentImageQualityHandler extends _VisionHandler {
  @override
  String get capability => 'quality.document_image';

  @override
  Future<WorkerTaskResult> handle({required WorkerTaskRequest request, required OcrEngine ocrEngine, required QwenTaskProcessor qwenProcessor, required String signingKey, required WorkerTaskMetrics metrics, bool Function()? isCancelled}) async =>
      success(request, vision.documentQuality(request.input.imageBytes!));
}

class DuplicateImageHandler extends _VisionHandler {
  @override
  String get capability => 'catalog.duplicate_image';

  @override
  Future<WorkerTaskResult> handle({required WorkerTaskRequest request, required OcrEngine ocrEngine, required QwenTaskProcessor qwenProcessor, required String signingKey, required WorkerTaskMetrics metrics, bool Function()? isCancelled}) async =>
      success(request, vision.duplicate(request.input.imageBytes!, request.input.compareImageBytes!));
}
