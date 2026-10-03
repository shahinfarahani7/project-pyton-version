import 'dart:developer' as developer;

import '../../contracts/worker_error.dart';
import '../../contracts/worker_task_request.dart';
import '../../contracts/worker_task_result.dart';
import '../../inference/llm/qwen_task_processor.dart';
import '../../inference/ocr/ocr_engine.dart';
import '../../runtime/checkpoint_manager.dart';
import '../../runtime/device_inference_plan.dart';
import '../../runtime/device_inference_policy_config.dart';
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
    final taskType = request.sourceTaskType.isNotEmpty
        ? request.sourceTaskType
        : request.type;
    final selection = DeviceInferencePlan.instance.selectionFor(
      taskType: taskType,
      wantsVision: hasImage,
    );
    if (selection != null && hasImage && !selection.multimodalEligible) {
      developer.log(
        '[DEVICE CONFIG] vision restricted reason=${selection.reason}; '
        'resident model stays loaded',
        name: 'EdgeMintTaskEngine',
      );
    }
    if (selection != null && !selection.admitted) {
      developer.log(
        '[MODEL ADMISSION] admitted=false reason=${selection.reason}; '
        'resident model stays loaded',
        name: 'EdgeMintTaskEngine',
      );
    }
    final stageOutputLimit = selection?.selectedOutputLimit(decision.answerClass) ??
        decision.effectiveOutputLimit;
    final sampling = selection == null
        ? null
        : GenerationSampling.forAnswerClass(decision.answerClass);

    final llmStart = DateTime.now();
    final staged = await GemmaStagedDirectGeneration.run(
      decision: decision,
      prompt: userText,
      maxStages: selection?.maxStages,
      hardMaxStages: selection?.hardMaxStages,
      executionBudget: decision.staged ? selection?.longFormBudget : null,
      readSignals: DeviceInferencePlan.instance.readSignals,
      generateStage: (stageIndex, stagePrompt) {
        return qwenProcessor
            .runDirectUserGeneration(
              stagePrompt,
              signingKey: signingKey,
              imageBytes: stageIndex == 0 && hasImage ? imageBytes : null,
              maxOutputTokens: stageOutputLimit,
              temperature: sampling?.temperature,
              topP: sampling?.topP,
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
      configuredOutputLimit: stageOutputLimit,
      generatedChunks: staged.generatedChunks,
      generatedTokens: staged.generatedTokens,
    );
    metrics.llmMs = DateTime.now().difference(llmStart).inMilliseconds;
    developer.log(
      decision.completionLog(
        generatedChunks: generation.generatedChunks,
        generatedTokens: generation.generatedTokens,
        truncated: decision.staged ? staged.truncated : generation.hitOutputLimit,
      ),
      name: 'EdgeMintTaskEngine',
    );

    return resultFor(
      request: request,
      generation: generation,
      metrics: metrics,
      truncated: decision.staged ? staged.truncated : null,
    );
  }

  static WorkerTaskResult resultFor({
    required WorkerTaskRequest request,
    required DirectGenerationReceipt generation,
    required WorkerTaskMetrics metrics,
    bool? truncated,
  }) {
    final reportedTruncated = truncated ??
        (generation.hitOutputLimit ||
            generation.stopReason == GemmaGenerationOutputLimit.longFormStageLimit);
    final evidence = <String, dynamic>{
      'rawText': generation.text,
      'modelTranscript': generation.text,
      'configuredOutputLimit': generation.configuredOutputLimit,
      'generatedChunks': generation.generatedChunks,
      'generatedTokens': generation.generatedTokens,
      'stopReason': generation.stopReason,
      'truncated': reportedTruncated,
    };
    final freeForm = _freeFormTextDirect(request);
    if (truncated == false) {
      return WorkerTaskResult(
        schemaVersion: request.schemaVersion,
        taskId: request.taskId,
        status: WorkerResultStatus.succeeded,
        output: evidence,
        metrics: metrics.toJson(),
      );
    }
    final stageLimited =
        generation.stopReason == GemmaGenerationOutputLimit.longFormStageLimit ||
        generation.stopReason == GemmaGenerationOutputLimit.leaseBudgetExhausted;
    if (stageLimited) {
      if (freeForm || request.options.allowTruncatedOutput) {
        return WorkerTaskResult(
          schemaVersion: request.schemaVersion,
          taskId: request.taskId,
          status: WorkerResultStatus.succeededWithTruncation,
          output: evidence,
          metrics: metrics.toJson(),
        );
      }
      return WorkerTaskResult(
        schemaVersion: request.schemaVersion,
        taskId: request.taskId,
        status: WorkerResultStatus.failed,
        output: evidence,
        metrics: metrics.toJson(),
        error: WorkerError(
          code: WorkerErrorCode.longFormIncomplete,
          message:
              'Long-form generation reached the stage safety limit '
              'while the text was still incomplete',
          retryable: false,
          stage: WorkerTaskStage.llm,
        ),
      );
    }
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
