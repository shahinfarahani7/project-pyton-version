import '../../contracts/worker_error.dart';
import '../../contracts/worker_task_request.dart';
import '../../contracts/worker_task_result.dart';
import '../../inference/llm/qwen_task_processor.dart';
import '../../inference/ocr/ocr_engine.dart';
import '../../runtime/checkpoint_manager.dart';
import '../../telemetry/worker_task_metrics.dart';
import 'task_handler.dart';

/// Sends portal intake to the on-device Gemma model (text and/or image).
class DirectPromptHandler implements TaskHandler {
  @override
  String get capability => 'text.direct.v1';

  @override
  Future<WorkerTaskResult> handle({
    required WorkerTaskRequest request,
    required OcrEngine ocrEngine,
    required QwenTaskProcessor qwenProcessor,
    required String signingKey,
    required WorkerTaskMetrics metrics,
    bool Function()? isCancelled,
    String? assignmentId,
    int? fenceToken,
    Future<void> Function(ChunkCheckpointRecord record)? onChunkCheckpoint,
  }) async {
    if (isCancelled?.call() == true) {
      throw const WorkerError(
        code: WorkerErrorCode.cancelled,
        message: 'Task cancelled',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
    }

    final userText = request.input.text?.trim() ?? '';
    final imageBytes = request.input.imageBytes;
    final hasImage = imageBytes != null && imageBytes.isNotEmpty;

    if (userText.isEmpty && !hasImage) {
      throw const WorkerError(
        code: WorkerErrorCode.invalidTask,
        message: 'User prompt or image is required for text.direct.v1',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
    }

    final llmStart = DateTime.now();
    final modelTranscript = await qwenProcessor.runDirectUserText(
      userText,
      signingKey: signingKey,
      imageBytes: hasImage ? imageBytes : null,
      maxOutputTokens: 512,
    );
    metrics.llmMs = DateTime.now().difference(llmStart).inMilliseconds;

    return WorkerTaskResult(
      schemaVersion: request.schemaVersion,
      taskId: request.taskId,
      status: WorkerResultStatus.succeeded,
      output: {
        'rawText': modelTranscript,
        'modelTranscript': modelTranscript,
      },
      metrics: metrics.toJson(),
    );
  }
}
