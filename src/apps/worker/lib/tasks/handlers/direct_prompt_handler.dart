import '../../contracts/worker_error.dart';
import '../../contracts/worker_task_request.dart';
import '../../contracts/worker_task_result.dart';
import '../../inference/llm/qwen_task_processor.dart';
import '../../inference/ocr/ocr_engine.dart';
import '../../runtime/checkpoint_manager.dart';
import '../../runtime/gemma4_e4b_gpu_benchmark.dart';
import '../../telemetry/worker_task_metrics.dart';
import 'ocr_pipeline_mixin.dart';
import 'task_handler.dart';

/// Sends portal intake to the on-device LLM without summarize/OCR contract shaping.
class DirectPromptHandler with OcrPipelineMixin implements TaskHandler {
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

    final parts = <String>[];
    final userText = request.input.text?.trim();
    if (userText != null && userText.isNotEmpty) {
      parts.add(userText);
    }

    if (!Gemma4E4bBenchmarkMode.active && request.input.imageBytes != null) {
      final ocr = await runOcr(request, ocrEngine, metrics);
      final ocrText = ocr.rawText.trim();
      if (ocrText.isNotEmpty) {
        parts.add(ocrText);
      }
    }

    final prompt = parts.join('\n\n').trim();
    if (prompt.isEmpty) {
      throw const WorkerError(
        code: WorkerErrorCode.invalidTask,
        message: 'User prompt is required for text.direct.v1',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
    }

    final llmStart = DateTime.now();
    final modelTranscript = await qwenProcessor.runDirectUserText(
      prompt,
      signingKey: signingKey,
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
