import '../../contracts/worker_task_request.dart';

import '../../contracts/worker_task_result.dart';

import '../../inference/llm/qwen_task_processor.dart';

import '../../inference/ocr/ocr_engine.dart';

import '../../runtime/checkpoint_manager.dart';

import '../../runtime/vision_runtime_manager.dart';

import '../../telemetry/worker_task_metrics.dart';

import 'task_handler.dart';



abstract class _VisionHandler implements TaskHandler {

  const _VisionHandler(this.visionRuntime);



  final VisionRuntimeManager visionRuntime;



  WorkerTaskResult success(

    WorkerTaskRequest request,

    Map<String, dynamic> data,

    String capability,

  ) =>

      WorkerTaskResult(

        schemaVersion: request.schemaVersion,

        taskId: request.taskId,

        status: WorkerResultStatus.succeeded,

        output: {

          'data': data,

          'visionRuntimeClass': visionRuntime.runtimeClassFor(capability),

        },

      );

}



class BlurryImageHandler extends _VisionHandler {

  BlurryImageHandler({VisionRuntimeManager? visionRuntime})

      : super(visionRuntime ?? VisionRuntimeManager());



  @override

  String get capability => 'quality.blurry_image';



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

    return success(

      request,

      visionRuntime.classifyBlur(request.input.imageBytes!),

      capability,

    );

  }

}



class DocumentImageQualityHandler extends _VisionHandler {

  DocumentImageQualityHandler({VisionRuntimeManager? visionRuntime})

      : super(visionRuntime ?? VisionRuntimeManager());



  @override

  String get capability => 'quality.document_image';



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

  }) async =>

      success(

        request,

        visionRuntime.classifyDocumentQuality(request.input.imageBytes!),

        capability,

      );

}



class DuplicateImageHandler extends _VisionHandler {

  DuplicateImageHandler({VisionRuntimeManager? visionRuntime})

      : super(visionRuntime ?? VisionRuntimeManager());



  @override

  String get capability => 'catalog.duplicate_image';



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

  }) async =>

      success(

        request,

        visionRuntime.classifyDuplicate(

          request.input.imageBytes!,

          request.input.compareImageBytes!,

        ),

        capability,

      );

}


