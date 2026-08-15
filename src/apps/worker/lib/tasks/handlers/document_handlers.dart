import 'dart:convert';

import '../../contracts/worker_error.dart';
import '../../contracts/worker_task_request.dart';
import '../../contracts/worker_task_result.dart';
import '../../inference/llm/prompt_templates.dart';
import '../../inference/llm/qwen_task_processor.dart';
import '../../inference/ocr/ocr_engine.dart';
import '../../inference/ocr/ocr_text_normalizer.dart';
import '../../telemetry/worker_task_metrics.dart';
import 'ocr_pipeline_mixin.dart';
import 'task_handler.dart';

class DocumentExtractHandler with OcrPipelineMixin implements TaskHandler {
  @override
  String get capability => 'document.extract.v1';

  @override
  Future<WorkerTaskResult> handle({
    required WorkerTaskRequest request,
    required OcrEngine ocrEngine,
    required QwenTaskProcessor qwenProcessor,
    required String signingKey,
    required WorkerTaskMetrics metrics,
    bool Function()? isCancelled,
  }) async {
    final ocr = await runOcr(request, ocrEngine, metrics);
    final llmStart = DateTime.now();
    final schemaJson = jsonEncode(request.options.outputSchema ?? {});
    final prompt = PromptTemplates.documentExtract(
      ocrText: ocr.rawText,
      ocrConfidence: ocr.averageConfidence,
      outputSchemaJson: schemaJson,
    );
    final data = await qwenProcessor.runJsonTask(
      prompt: prompt,
      outputSchema: request.options.outputSchema,
      signingKey: signingKey,
    );
    metrics.llmMs = DateTime.now().difference(llmStart).inMilliseconds;
    return WorkerTaskResult(
      schemaVersion: request.schemaVersion,
      taskId: request.taskId,
      status: WorkerResultStatus.succeeded,
      output: {
        'rawText': ocr.rawText,
        'ocrLines': ocr.lines.map((l) => l.toJson()).toList(),
        'data': data,
      },
      metrics: metrics.toJson(),
    );
  }
}

class DocumentClassifyHandler with OcrPipelineMixin implements TaskHandler {
  @override
  String get capability => 'document.classify.v1';

  @override
  Future<WorkerTaskResult> handle({
    required WorkerTaskRequest request,
    required OcrEngine ocrEngine,
    required QwenTaskProcessor qwenProcessor,
    required String signingKey,
    required WorkerTaskMetrics metrics,
    bool Function()? isCancelled,
  }) async {
    final ocr = await runOcr(request, ocrEngine, metrics);
    final labels = request.options.allowedLabels ?? ['receipt', 'invoice', 'other'];
    final llmStart = DateTime.now();
    final prompt = PromptTemplates.documentClassify(
      ocrText: ocr.rawText,
      allowedLabelsJson: jsonEncode(labels),
    );
    final data = await qwenProcessor.runJsonTask(
      prompt: prompt,
      signingKey: signingKey,
    );
    metrics.llmMs = DateTime.now().difference(llmStart).inMilliseconds;
    return WorkerTaskResult(
      schemaVersion: request.schemaVersion,
      taskId: request.taskId,
      status: WorkerResultStatus.succeeded,
      output: {
        'rawText': ocr.rawText,
        'ocrLines': ocr.lines.map((l) => l.toJson()).toList(),
        'data': data,
      },
      metrics: metrics.toJson(),
    );
  }
}

class DocumentSummarizeHandler with OcrPipelineMixin implements TaskHandler {
  @override
  String get capability => 'document.summarize.v1';

  @override
  Future<WorkerTaskResult> handle({
    required WorkerTaskRequest request,
    required OcrEngine ocrEngine,
    required QwenTaskProcessor qwenProcessor,
    required String signingKey,
    required WorkerTaskMetrics metrics,
    bool Function()? isCancelled,
  }) async {
    final ocr = await runOcr(request, ocrEngine, metrics);
    final llmStart = DateTime.now();
    final prompt = PromptTemplates.documentSummarize(ocrText: ocr.rawText);
    final data = await qwenProcessor.runJsonTask(
      prompt: prompt,
      signingKey: signingKey,
    );
    metrics.llmMs = DateTime.now().difference(llmStart).inMilliseconds;
    return WorkerTaskResult(
      schemaVersion: request.schemaVersion,
      taskId: request.taskId,
      status: WorkerResultStatus.succeeded,
      output: {
        'rawText': ocr.rawText,
        'ocrLines': ocr.lines.map((l) => l.toJson()).toList(),
        'data': data,
      },
      metrics: metrics.toJson(),
    );
  }
}

class TextClassifyHandler implements TaskHandler {
  @override
  String get capability => 'text.classify.v1';

  @override
  Future<WorkerTaskResult> handle({
    required WorkerTaskRequest request,
    required OcrEngine ocrEngine,
    required QwenTaskProcessor qwenProcessor,
    required String signingKey,
    required WorkerTaskMetrics metrics,
    bool Function()? isCancelled,
  }) async {
    final labels = request.options.allowedLabels ?? ['payment', 'ticketing', 'login', 'other'];
    final llmStart = DateTime.now();
    final prompt = PromptTemplates.textClassify(
      inputText: request.input.text!,
      allowedLabelsJson: jsonEncode(labels),
    );
    final data = await qwenProcessor.runJsonTask(
      prompt: prompt,
      signingKey: signingKey,
    );
    metrics.llmMs = DateTime.now().difference(llmStart).inMilliseconds;
    return WorkerTaskResult(
      schemaVersion: request.schemaVersion,
      taskId: request.taskId,
      status: WorkerResultStatus.succeeded,
      output: {'data': data},
      metrics: metrics.toJson(),
    );
  }
}
