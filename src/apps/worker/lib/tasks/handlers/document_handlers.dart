import 'dart:convert';

import '../../contracts/worker_error.dart';
import '../../contracts/task_contract_catalog.dart';
import '../../contracts/worker_task_request.dart';
import '../../contracts/worker_task_result.dart';
import '../../inference/llm/prompt_templates.dart';
import '../../inference/llm/qwen_task_processor.dart';
import '../../runtime/checkpoint_manager.dart';
import '../../inference/ocr/ocr_engine.dart';
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
    String? assignmentId,
    int? fenceToken,
    Future<void> Function(ChunkCheckpointRecord record)? onChunkCheckpoint,
  }) async {
    final ocr = await runOcr(request, ocrEngine, metrics);
    final llmStart = DateTime.now();
    final contract = TaskContractCatalog.forType(request.sourceTaskType);
    final schema =
        request.options.outputSchema ??
        contract?.outputSchema ??
        const <String, dynamic>{};
    final prompt = PromptTemplates.contractedTask(
      taskType: request.sourceTaskType,
      instruction:
          contract?.instruction ??
          'Extract requested fields without invention.',
      inputJson: jsonEncode({
        'ocrText': ocr.rawText,
        'ocrConfidence': ocr.averageConfidence,
        ...request.input.data,
      }),
      outputSchemaJson: jsonEncode(schema),
    );
    final data = await qwenProcessor.runJsonTask(
      prompt: prompt,
      outputSchema: schema,
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
    String? assignmentId,
    int? fenceToken,
    Future<void> Function(ChunkCheckpointRecord record)? onChunkCheckpoint,
  }) async {
    final ocr = await runOcr(request, ocrEngine, metrics);
    final labels =
        request.options.allowedLabels ?? ['receipt', 'invoice', 'other'];
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
    String? assignmentId,
    int? fenceToken,
    Future<void> Function(ChunkCheckpointRecord record)? onChunkCheckpoint,
  }) async {
    final ocr = await runOcr(request, ocrEngine, metrics);
    final llmStart = DateTime.now();
    final data = await qwenProcessor.runSummarizeJsonTask(
      inputText: ocr.rawText,
      userInstructions: request.input.data['instructions'] as String?,
      constraints: request.options.summarize,
      signingKey: signingKey,
      assignmentId: assignmentId,
      fenceToken: fenceToken,
      onChunkCheckpoint: onChunkCheckpoint,
      isCancelled: isCancelled,
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

class TextSummarizeHandler implements TaskHandler {
  @override
  String get capability => 'text.summarize.v1';

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
    final inputText = request.input.text;

    if (inputText == null || inputText.trim().isEmpty) {
      throw const WorkerError(
        code: WorkerErrorCode.invalidTask,
        message: 'Text input is required for text.summarize.v1',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
    }

    if (isCancelled?.call() == true) {
      throw const WorkerError(
        code: WorkerErrorCode.cancelled,
        message: 'Task cancelled',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
    }

    final llmStart = DateTime.now();

    final data = await qwenProcessor.runSummarizeJsonTask(
      inputText: inputText,
      userInstructions: request.input.data['instructions'] as String?,
      constraints: request.options.summarize,
      signingKey: signingKey,
      assignmentId: assignmentId,
      fenceToken: fenceToken,
      onChunkCheckpoint: onChunkCheckpoint,
      isCancelled: isCancelled,
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
    String? assignmentId,
    int? fenceToken,
    Future<void> Function(ChunkCheckpointRecord record)? onChunkCheckpoint,
  }) async {
    final contract = TaskContractCatalog.forType(request.sourceTaskType);
    final labels = request.options.allowedLabels ?? const <String>[];
    final llmStart = DateTime.now();
    final schema = request.options.outputSchema ?? contract?.outputSchema;
    final input = <String, dynamic>{
      if (request.input.hasText) 'text': request.input.text,
      ...request.input.data,
      if (labels.isNotEmpty) 'allowedLabels': labels,
    };
    final prompt = contract == null
        ? PromptTemplates.textClassify(
            inputText: request.input.text!,
            allowedLabelsJson: jsonEncode(labels),
          )
        : PromptTemplates.contractedTask(
            taskType: request.sourceTaskType,
            instruction: contract.instruction,
            inputJson: jsonEncode(input),
            outputSchemaJson: jsonEncode(schema),
          );
    final data = await qwenProcessor.runJsonTask(
      prompt: prompt,
      outputSchema: schema,
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
