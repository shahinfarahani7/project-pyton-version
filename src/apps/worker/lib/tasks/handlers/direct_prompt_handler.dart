import 'dart:developer' as developer;

import '../../contracts/worker_error.dart';
import '../../contracts/worker_task_request.dart';
import '../../contracts/worker_task_result.dart';
import '../../inference/llm/qwen_task_processor.dart';
import '../../inference/ocr/ocr_engine.dart';
import '../../runtime/checkpoint_manager.dart';
import '../../runtime/gemma_generation_output_limit.dart';
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

    final decision = GemmaGenerationOutputLimit.resolveTextDirect(
      prompt: userText,
      explicitMaxOutputTokens: request.options.maxOutputTokens,
      maxOutputTokensSpecified: request.options.maxOutputTokensSpecified,
      longForm: request.options.longForm,
    );
    developer.log(decision.logLine, name: 'EdgeMintTaskEngine');

    final llmStart = DateTime.now();
    final staged = await GemmaStagedDirectGeneration.run(
      decision: decision,
      prompt: userText,
      generateStage: (stageIndex, stagePrompt) {
        return qwenProcessor
            .runDirectUserGeneration(
              stagePrompt,
              signingKey: signingKey,
              imageBytes: stageIndex == 0 && hasImage ? imageBytes : null,
              maxOutputTokens: decision.effectiveOutputLimit,
            )
            .then(
              (receipt) => GemmaStagePiece(
                text: receipt.text,
                stopReason: receipt.stopReason,
                generatedChunks: receipt.generatedChunks,
                generatedTokens: receipt.generatedTokens,
              ),
            );
      },
    );
    final generation = DirectGenerationReceipt(
      text: staged.text,
      stopReason: staged.stopReason,
      configuredOutputLimit: decision.effectiveOutputLimit,
      generatedChunks: staged.generatedChunks,
      generatedTokens: staged.generatedTokens,
    );
    metrics.llmMs = DateTime.now().difference(llmStart).inMilliseconds;
    developer.log(
      decision.completionLog(
        generatedChunks: generation.generatedChunks,
        generatedTokens: generation.generatedTokens,
        truncated: generation.hitOutputLimit,
      ),
      name: 'EdgeMintTaskEngine',
    );

    return resultFor(
      request: request,
      generation: generation,
      metrics: metrics,
    );
  }

  static WorkerTaskResult resultFor({
    required WorkerTaskRequest request,
    required DirectGenerationReceipt generation,
    required WorkerTaskMetrics metrics,
  }) {
    final evidence = <String, dynamic>{
      'rawText': generation.text,
      'modelTranscript': generation.text,
      'configuredOutputLimit': generation.configuredOutputLimit,
      'generatedChunks': generation.generatedChunks,
      'generatedTokens': generation.generatedTokens,
      'stopReason': generation.stopReason,
      'truncated': generation.hitOutputLimit,
    };
    final freeForm = _freeFormTextDirect(request);
    final partialSuccess = generation.hitOutputLimit &&
        freeForm &&
        generation.text.trim().isNotEmpty;
    if (generation.hitOutputLimit &&
        !partialSuccess &&
        !request.options.allowTruncatedOutput) {
      return WorkerTaskResult(
        schemaVersion: request.schemaVersion,
        taskId: request.taskId,
        status: WorkerResultStatus.failed,
        output: evidence,
        metrics: metrics.toJson(),
        error: WorkerError(
          code: WorkerErrorCode.outputSchemaMismatch,
          message:
              'Generation hit output limit '
              '(${generation.generatedChunks}/${generation.configuredOutputLimit} chunks, '
              'stopReason=${GemmaGenerationOutputLimit.outputLimit})',
          retryable: false,
          stage: WorkerTaskStage.llm,
        ),
      );
    }
    return WorkerTaskResult(
      schemaVersion: request.schemaVersion,
      taskId: request.taskId,
      status: WorkerResultStatus.succeeded,
      output: evidence,
      metrics: metrics.toJson(),
    );
  }

  /// Free-form text.direct has no output schema. A non-empty cap hit is a
  /// truncated success. Structured contracts still fail when incomplete.
  static bool _freeFormTextDirect(WorkerTaskRequest request) {
    final options = request.options;
    return options.outputSchema == null &&
        options.summarize == null &&
        (options.allowedLabels == null || options.allowedLabels!.isEmpty);
  }
}
