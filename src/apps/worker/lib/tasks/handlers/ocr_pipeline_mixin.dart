import '../../contracts/worker_error.dart';
import '../../contracts/worker_task_request.dart';
import '../../inference/ocr/ocr_engine.dart';
import '../../inference/ocr/ocr_text_normalizer.dart';
import '../../telemetry/worker_task_metrics.dart';

mixin OcrPipelineMixin {
  Future<OcrRecognitionResult> runOcr(
    WorkerTaskRequest request,
    OcrEngine ocrEngine,
    WorkerTaskMetrics metrics,
  ) async {
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
    return OcrRecognitionResult(
      lines: lines,
      rawText: OcrTextNormalizer.joinRawText(lines),
      averageConfidence: metrics.averageOcrConfidence!,
    );
  }
}
