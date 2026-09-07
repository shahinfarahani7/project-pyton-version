import '../../contracts/worker_error.dart';
import '../../contracts/worker_task_request.dart';
import '../../contracts/worker_task_result.dart';
import '../../inference/llm/qwen_task_processor.dart';
import '../../runtime/checkpoint_manager.dart';
import '../../inference/ocr/ocr_engine.dart';
import '../../inference/ocr/ocr_text_normalizer.dart';
import '../../telemetry/worker_task_metrics.dart';
import 'task_handler.dart';

class OcrExtractTextHandler implements TaskHandler {
  @override
  String get capability => 'ocr.extract_text.v1';

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
    final ocrStart = DateTime.now();
    final ocr = await ocrEngine.recognize(
      imageBytes: request.input.imageBytes!,
      minConfidence: request.options.minOcrConfidence,
    );
    metrics.ocrMs = DateTime.now().difference(ocrStart).inMilliseconds;
    final lines = OcrTextNormalizer.normalizeLines(ocr.lines);
    metrics.averageOcrConfidence = OcrTextNormalizer.averageConfidence(lines);
    if (lines.isEmpty) {
      throw const WorkerError(
        code: WorkerErrorCode.ocrNoText,
        message: 'OCR produced no text lines',
        retryable: true,
        stage: WorkerTaskStage.ocr,
      );
    }
    if (metrics.averageOcrConfidence! < request.options.minOcrConfidence) {
      throw const WorkerError(
        code: WorkerErrorCode.ocrLowConfidence,
        message: 'OCR confidence is below the configured threshold.',
        retryable: true,
        stage: WorkerTaskStage.ocr,
      );
    }
    return WorkerTaskResult(
      schemaVersion: request.schemaVersion,
      taskId: request.taskId,
      status: WorkerResultStatus.succeeded,
      output: {
        'rawText': OcrTextNormalizer.joinRawText(lines),
        'ocrLines': lines.map((l) => l.toJson()).toList(),
      },
      metrics: metrics.toJson(),
    );
  }
}
