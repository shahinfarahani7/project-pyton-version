import 'dart:convert';

import 'dart:typed_data';



import '../../contracts/task_contract_catalog.dart';

import '../../contracts/worker_error.dart';

import '../../contracts/worker_task_request.dart';

import '../../contracts/worker_task_result.dart';

import '../../inference/llm/prompt_templates.dart';

import '../../inference/llm/qwen_task_processor.dart';

import '../../inference/ocr/ocr_engine.dart';

import '../../runtime/checkpoint_manager.dart';

import '../../runtime/vision_runtime_manager.dart';

import '../../telemetry/worker_task_metrics.dart';

import '../../validation/json_output_validator.dart';

import '../../validation/vision_consistency_validator.dart';

import '../../validation/vision_output_normalizer.dart';

import 'task_handler.dart';



class VisionAnalyzeHandler implements TaskHandler {

  VisionAnalyzeHandler({VisionRuntimeManager? visionRuntime})

      : _visionRuntime = visionRuntime ?? VisionRuntimeManager();



  final VisionRuntimeManager _visionRuntime;



  @override

  String get capability => 'vision.analyze.v1';



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

    if (contract == null ||

        !TaskContractCatalog.visionTypes.contains(request.sourceTaskType)) {

      throw WorkerError(

        code: WorkerErrorCode.unsupportedTaskType,

        message: 'No vision contract for ${request.sourceTaskType}',

        retryable: false,

        stage: WorkerTaskStage.validation,

      );

    }

    final started = DateTime.now();

    final raw = await _visionRuntime.inferVlm(

      imageBytes: request.input.imageBytes!,

      prompt: PromptTemplates.visionTask(

        taskType: request.sourceTaskType,

        instruction: contract.instruction,

        outputSchemaJson: jsonEncode(contract.outputSchema),

        contextJson: jsonEncode(request.input.data),

      ),

    );

    var data = JsonOutputValidator.parseJsonObject(raw);

    final directError = data == null

        ? null

        : JsonOutputValidator.validateSchema(data, contract.outputSchema);

    final consistencyError = data == null

        ? null

        : VisionConsistencyValidator.validate(request.sourceTaskType, data);

    if (data == null || directError != null || consistencyError != null) {

      try {

        data = await qwenProcessor.runJsonTask(

          prompt: PromptTemplates.contractedTask(

            taskType: '${request.sourceTaskType}.json_repair',

            instruction: 'Repair the vision model JSON without adding new visual claims. Resolve the reported schema or internal-consistency issue using only the existing output.',

            inputJson: jsonEncode({

              'visionOutput': raw,

              'validationIssue':

                  directError?.message ?? consistencyError?.message,

            }),

            outputSchemaJson: jsonEncode(contract.outputSchema),

          ),

          outputSchema: contract.outputSchema,

          signingKey: signingKey,

        );

      } on WorkerError {

        data = VisionOutputNormalizer.fallback(request.sourceTaskType);

      }

    }

    data = VisionOutputNormalizer.normalize(request.sourceTaskType, data);

    final normalizedSchema = JsonOutputValidator.validateSchema(

      data,

      contract.outputSchema,

    );

    var repairedConsistency = VisionConsistencyValidator.validate(

      request.sourceTaskType,

      data,

    );

    if (normalizedSchema != null || repairedConsistency != null) {

      data = VisionOutputNormalizer.fallback(request.sourceTaskType);

      repairedConsistency = VisionConsistencyValidator.validate(

        request.sourceTaskType,

        data,

      );

    }

    if (repairedConsistency != null) throw repairedConsistency;

    metrics.llmMs = DateTime.now().difference(started).inMilliseconds;

    return WorkerTaskResult(

      schemaVersion: request.schemaVersion,

      taskId: request.taskId,

      status: WorkerResultStatus.succeeded,

      output: {

        'data': data,

        'visionRuntimeClass': _visionRuntime.runtimeClassFor(capability),

      },

      metrics: metrics.toJson(),

    );

  }

}



class RemoveBackgroundHandler implements TaskHandler {

  RemoveBackgroundHandler({VisionRuntimeManager? visionRuntime})

      : _visionRuntime = visionRuntime ?? VisionRuntimeManager();



  final VisionRuntimeManager _visionRuntime;



  @override

  String get capability => 'image.remove_background.v1';



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

    final started = DateTime.now();

    final png = await _visionRuntime.segmentBackground(

      imageBytes: request.input.imageBytes!,

    );

    metrics.llmMs = DateTime.now().difference(started).inMilliseconds;

    return WorkerTaskResult(

      schemaVersion: request.schemaVersion,

      taskId: request.taskId,

      status: WorkerResultStatus.succeeded,

      output: {

        'mimeType': 'image/png',

        'imageBase64': base64Encode(png),

        'sizeBytes': png.length,

        'segmentationModel': 'MediaPipe SelfieSegmenter float16',

        'visionRuntimeClass': _visionRuntime.runtimeClassFor(capability),

      },

      metrics: metrics.toJson(),

    );

  }

}


