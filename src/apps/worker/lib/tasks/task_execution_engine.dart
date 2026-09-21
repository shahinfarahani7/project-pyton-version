import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../api/worker_assignment_models.dart';
import '../contracts/worker_error.dart';
import '../contracts/worker_task_request.dart';
import '../contracts/worker_task_result.dart';
import '../inference/llm/qwen_task_processor.dart';
import '../inference/ocr/ocr_engine.dart';
import '../inference/ocr/ocr_models.dart';
import '../models/worker_model_catalog.dart';
import '../models/worker_vision_model_catalog.dart';
import '../runtime/device_tier_policy.dart';
import '../runtime/inference_adapter.dart';
import '../runtime/assignment_event_reporter.dart';
import '../runtime/execution_plan_runner.dart';
import '../runtime/runtime_exclusive_group_enforcer.dart';
import '../runtime/vision_runtime_catalog.dart';
import '../runtime/runtime_exceptions.dart';
import '../runtime/worker_model_installer.dart';
import '../tasks/idempotency_store.dart';
import '../tasks/task_type_mapper.dart';
import '../telemetry/worker_task_metrics.dart';
import '../validation/task_input_validator.dart';
import 'mobile_task_dispatcher.dart';

class TaskExecutionContext {
  const TaskExecutionContext({
    required this.assignment,
    required this.manifest,
    required this.inputBytes,
    this.compareImageBytes,
    required this.isImageInput,
  });

  final WorkerAssignment assignment;
  final Map<String, dynamic> manifest;
  final Uint8List inputBytes;
  final Uint8List? compareImageBytes;
  final bool isImageInput;
}

class TaskExecutionEngine {
  TaskExecutionEngine({
    required OcrEngine ocrEngine,
    required QwenTaskProcessor qwenProcessor,
    MobileTaskDispatcher? dispatcher,
    IdempotencyStore? idempotencyStore,
    ExecutionPlanRunner? executionPlanRunner,
    RuntimeExclusiveGroupEnforcer? exclusiveGroupEnforcer,
  }) : _ocrEngine = ocrEngine,
       _qwenProcessor = qwenProcessor,
       _dispatcher = dispatcher ?? MobileTaskDispatcher(),
       _idempotency = idempotencyStore ?? IdempotencyStore(),
       _executionPlanRunner = executionPlanRunner,
       _exclusiveGroupEnforcer = exclusiveGroupEnforcer;

  final OcrEngine _ocrEngine;
  final QwenTaskProcessor _qwenProcessor;
  final MobileTaskDispatcher _dispatcher;
  final IdempotencyStore _idempotency;
  final ExecutionPlanRunner? _executionPlanRunner;
  final RuntimeExclusiveGroupEnforcer? _exclusiveGroupEnforcer;

  WorkerTaskResult? _lastResult;
  bool _running = false;

  Future<bool>? _modelReadyFuture;

  WorkerTaskResult? get lastResult => _lastResult;

  ExecutionPlanRunner get executionPlanRunner =>
      _executionPlanRunner ??
      ExecutionPlanRunner(
        modelRuntime: _qwenProcessor.modelRuntimeManager,
        exclusiveGroupEnforcer: _exclusiveGroupEnforcer,
      );

  Future<List<String>> advertisedCapabilities({
    required bool qwenReady,
    required bool ocrReady,
  }) async {
    final capabilities = <String>[];

    for (final capability in _dispatcher.capabilities) {
      if (TaskTypeMapper.requiresOcr(capability) && !ocrReady) {
        continue;
      }

      if (TaskTypeMapper.requiresLlm(capability) && !qwenReady) {
        continue;
      }

      capabilities.add(capability);
    }

    return capabilities;
  }

  Future<InferenceOutput> execute({
    required TaskExecutionContext context,
    required String signingKey,
    required int freeStorageMb,
    bool Function()? isCancelled,
    AssignmentEventReporter? eventReporter,
  }) async {
    if (_running) {
      throw StateError('Concurrent task execution is not allowed');
    }

    _running = true;

    try {
      final request = _buildRequest(context);
      _enforceServerExecutionGrant(context.assignment);

      developer.log(
        '[TASK START] '
        'taskId=${request.taskId} '
        'type=${request.type} '
        'hasText=${request.input.hasText} '
        'hasImage=${request.input.hasImage}',
        name: 'EdgeMintTaskEngine',
      );

      // -----------------------------------------------------------------------
      // Idempotency
      // -----------------------------------------------------------------------

      final cached = _idempotency.get(request.idempotencyKey);

      if (cached != null) {
        developer.log(
          '[TASK CACHE HIT] '
          'taskId=${request.taskId}',
          name: 'EdgeMintTaskEngine',
        );

        _lastResult = cached;
        return _toInferenceOutput(cached);
      }

      // -----------------------------------------------------------------------
      // Validation
      // -----------------------------------------------------------------------

      final validationError = TaskInputValidator.validate(request);

      if (validationError != null) {
        developer.log(
          '[TASK VALIDATION FAILED] '
          'taskId=${request.taskId} '
          'type=${request.type} '
          'code=${validationError.codeName} '
          'message=${validationError.message}',
          name: 'EdgeMintTaskEngine',
        );

        final result = _failedResult(request, validationError);

        _lastResult = result;

        return _toInferenceOutput(result);
      }

      final v1Type = request.type;

      // -----------------------------------------------------------------------
      // Device capability check
      // -----------------------------------------------------------------------

      final tier = DeviceTierPolicy.fromFreeStorageMb(freeStorageMb);

      final requiresOcr = TaskTypeMapper.requiresOcr(v1Type);

      final requiresLlm = TaskTypeMapper.requiresLlm(
        v1Type,
        ocrOnly: request.options.ocrOnly,
      );
      final usesExecutionPlan =
          (requiresLlm && _qwenProcessor.requiresNativeRuntime) ||
          VisionRuntimeCatalog.isVisionCapability(v1Type);

      if (requiresOcr &&
          requiresLlm &&
          !DeviceTierPolicy.allowsCombinedOcrLlm(tier)) {
        final result = _failedResult(
          request,
          const WorkerError(
            code: WorkerErrorCode.outOfMemoryRisk,
            message: 'Device tier too low for combined OCR+LLM',
            retryable: true,
            stage: WorkerTaskStage.validation,
          ),
        );

        _lastResult = result;

        return _toInferenceOutput(result);
      }

      // -----------------------------------------------------------------------
      // Handler
      // -----------------------------------------------------------------------

      final handler = _dispatcher.handlerFor(v1Type);

      if (handler == null) {
        developer.log(
          '[TASK HANDLER MISSING] '
          'taskId=${request.taskId} '
          'type=$v1Type',
          name: 'EdgeMintTaskEngine',
        );

        final result = _failedResult(
          request,
          WorkerError(
            code: WorkerErrorCode.unsupportedTaskType,
            message: 'No handler for $v1Type',
            retryable: false,
            stage: WorkerTaskStage.validation,
          ),
        );

        _lastResult = result;

        return _toInferenceOutput(result);
      }

      developer.log(
        '[TASK HANDLER] '
        'taskId=${request.taskId} '
        'type=$v1Type '
        'handler=${handler.runtimeType}',
        name: 'EdgeMintTaskEngine',
      );

      // -----------------------------------------------------------------------
      // OCR readiness
      // -----------------------------------------------------------------------

      if (requiresOcr) {
        final ocrReady = await _ocrEngine.isReady();

        if (!ocrReady) {
          developer.log(
            '[OCR LOAD] '
            'taskId=${request.taskId}',
            name: 'EdgeMintTaskEngine',
          );

          try {
            await _ocrEngine.ensureLoaded();
          } catch (error, stackTrace) {
            developer.log(
              '[OCR LOAD ERROR] $error',
              name: 'EdgeMintTaskEngine',
              error: error,
              stackTrace: stackTrace,
            );

            final result = _failedResult(
              request,
              const WorkerError(
                code: WorkerErrorCode.modelNotAvailable,
                message: 'OCR models are not available',
                retryable: true,
                stage: WorkerTaskStage.ocr,
              ),
            );

            _lastResult = result;

            return _toInferenceOutput(result);
          }
        }
      }

      // -----------------------------------------------------------------------
      // LLM readiness (load before fresh-session guard)
      // -----------------------------------------------------------------------

      if (requiresLlm) {
        if (_qwenProcessor.requiresNativeRuntime) {
          _modelReadyFuture ??= WorkerModelInstaller.ensureReady();
          final llmReady = await _modelReadyFuture!;
          _modelReadyFuture = null;
          if (!llmReady) {
            final result = _failedResult(
              request,
              const WorkerError(
                code: WorkerErrorCode.modelNotAvailable,
                message: 'Primary model is not resident',
                retryable: true,
                stage: WorkerTaskStage.llm,
              ),
            );
            _lastResult = result;
            return _toInferenceOutput(result);
          }
        }
        try {
          developer.log(
            '[LLM RESIDENT LOAD] taskId=${request.taskId}',
            name: 'EdgeMintTaskEngine',
          );
          await _qwenProcessor.ensureRuntimeResident(signingKey: signingKey);
          developer.log(
            '[LLM RESIDENT READY] taskId=${request.taskId}',
            name: 'EdgeMintTaskEngine',
          );
        } catch (error, stackTrace) {
          developer.log(
            '[LLM RESIDENT ERROR] taskId=${request.taskId} error=$error',
            name: 'EdgeMintTaskEngine',
            error: error,
            stackTrace: stackTrace,
          );
          throw WorkerError(
            code: WorkerErrorCode.modelNotAvailable,
            message: '$error',
            retryable: true,
            stage: WorkerTaskStage.llm,
          );
        }
      }

      // -----------------------------------------------------------------------
      // Metrics
      // -----------------------------------------------------------------------

      final metrics = WorkerTaskMetrics();

      metrics.inputBytes = context.inputBytes.length;

      // -----------------------------------------------------------------------
      // Execute
      // -----------------------------------------------------------------------

      try {
        if (isCancelled?.call() == true) {
          throw const WorkerError(
            code: WorkerErrorCode.cancelled,
            message: 'Task cancelled',
            retryable: false,
            stage: WorkerTaskStage.validation,
          );
        }

        developer.log(
          '[TASK EXECUTE] '
          'taskId=${request.taskId} '
          'type=$v1Type '
          'ocr=$requiresOcr '
          'llm=$requiresLlm',
          name: 'EdgeMintTaskEngine',
        );

        Future<WorkerTaskResult> invokeHandler() => handler.handle(
          request: request,
          ocrEngine: _ocrEngine,
          qwenProcessor: _qwenProcessor,
          signingKey: signingKey,
          metrics: metrics,
          isCancelled: isCancelled,
          assignmentId: context.assignment.assignmentId,
          fenceToken: context.assignment.fenceToken,
          onChunkCheckpoint: eventReporter?.reportChunkCheckpoint,
        );

        final planRunner = executionPlanRunner;
        WorkerTaskResult result;
        if (usesExecutionPlan) {
          final plan = ExecutionPlanCatalog.forTaskType(
            v1Type,
            ocrOnly: request.options.ocrOnly,
          );
          result = await planRunner.runPlanForScope(
            plan: plan,
            assignmentId: context.assignment.assignmentId,
            fenceToken: context.assignment.fenceToken,
            executeStage: (_) => invokeHandler(),
            context: ExecutionPlanRunContext(
              onProgress: (event) async {
                developer.log(
                  '[PLAN PROGRESS] '
                  'taskId=${request.taskId} '
                  'stage=${event.stage.name} '
                  'progress=${event.progressMilli}',
                  name: 'EdgeMintTaskEngine',
                );
                await eventReporter?.reportPlanProgress(event);
              },
            ),
          );
        } else {
          try {
            result = await invokeHandler();
          } on StaleFenceException {
            rethrow;
          }
        }

        final enriched = WorkerTaskResult(
          schemaVersion: result.schemaVersion,
          taskId: result.taskId,
          status: result.status,
          output: result.output,
          metrics: {...result.metrics, ...metrics.toJson()},
          modelInfo: {
            'ocrDetector': PaddleOcrModelCatalog.detectorVersion,
            'ocrRecognizer': PaddleOcrModelCatalog.recognizerVersion,
            'llm': request.type == TaskTypeMapper.visionAnalyze
                ? WorkerVisionModelCatalog.displayName
                : request.type == TaskTypeMapper.removeBackground
                ? 'MediaPipe SelfieSegmenter float16'
                : WorkerModelCatalog.displayName,
            'runtime': request.type == TaskTypeMapper.removeBackground
                ? 'MediaPipe Tasks Vision/TFLite'
                : request.type == TaskTypeMapper.visionAnalyze
                ? 'LiteRT-LM/flutter_gemma'
                : 'MediaPipe/flutter_gemma',
          },
          error: result.error,
        );

        _idempotency.put(request.idempotencyKey, enriched);

        _lastResult = enriched;

        developer.log(
          '[TASK COMPLETED] '
          'taskId=${request.taskId} '
          'type=$v1Type '
          'status=${enriched.status.name}',
          name: 'EdgeMintTaskEngine',
        );

        return _toInferenceOutput(enriched);
      } on StaleFenceException catch (error, stackTrace) {
        developer.log(
          '[TASK FENCE REJECTED] '
          'taskId=${request.taskId} '
          'error=$error',
          name: 'EdgeMintTaskEngine',
          error: error,
          stackTrace: stackTrace,
        );

        final result = _failedResult(
          request,
          WorkerError(
            code: WorkerErrorCode.invalidTask,
            message: '$error',
            retryable: false,
            stage: WorkerTaskStage.validation,
          ),
        );

        _lastResult = result;
        return _toInferenceOutput(result);
      } on WorkerError catch (error, stackTrace) {
        developer.log(
          '[TASK EXECUTION ERROR] '
          'type=${request.type} '
          'taskId=${request.taskId} '
          'code=${error.codeName} '
          'error=${error.message}',
          name: 'EdgeMintTaskEngine',
          error: error,
          stackTrace: stackTrace,
        );

        final result = _failedResult(
          request,
          error,
          retryable: error.retryable,
        );

        _idempotency.put(request.idempotencyKey, result);

        _lastResult = result;

        return _toInferenceOutput(result);
      } catch (error, stackTrace) {
        developer.log(
          '[TASK EXECUTION ERROR] '
          'type=${request.type} '
          'taskId=${request.taskId} '
          'error=$error',
          name: 'EdgeMintTaskEngine',
          error: error,
          stackTrace: stackTrace,
        );

        final result = _failedResult(
          request,
          WorkerError(
            code: WorkerErrorCode.internalError,
            message: '$error',
            retryable: true,
            stage: WorkerTaskStage.llm,
          ),
        );

        _lastResult = result;

        return _toInferenceOutput(result);
      }
    } finally {
      _running = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Request builder
  // ---------------------------------------------------------------------------

  WorkerTaskRequest _buildRequest(TaskExecutionContext context) {
    final manifest = context.manifest;

    final optionsJson = manifest['options'] as Map<String, dynamic>?;

    final options = WorkerTaskOptions.fromJson(optionsJson);

    final v1Type =
        TaskTypeMapper.toV1(context.assignment.taskType) ??
        context.assignment.taskType;

    final String? text;

    if (context.isImageInput) {
      text =
          manifest['inputText'] as String? ??
          manifest['contentText'] as String? ??
          manifest['prompt'] as String?;
    } else {
      text =
          manifest['inputText'] as String? ??
          manifest['contentText'] as String? ??
          manifest['prompt'] as String? ??
          utf8.decode(context.inputBytes);
    }

    developer.log(
      '[TASK BUILD] '
      'backendType=${context.assignment.taskType} '
      'v1Type=$v1Type '
      'isImage=${context.isImageInput} '
      'textChars=${text?.length ?? 0}',
      name: 'EdgeMintTaskEngine',
    );

    return WorkerTaskRequest(
      schemaVersion: manifest['schemaVersion'] as String? ?? '1.0',
      taskId: context.assignment.taskId ?? context.assignment.assignmentId,
      idempotencyKey:
          manifest['idempotencyKey'] as String? ?? context.assignment.attemptId,
      type: v1Type,
      sourceTaskType: context.assignment.taskType,
      input: WorkerTaskInput(
        imageBytes: context.isImageInput ? context.inputBytes : null,
        compareImageBytes: context.compareImageBytes,
        text: text,
        imageUri: manifest['imageUri'] as String?,
        data: {
          ...Map<String, dynamic>.from(
            (manifest['inputData'] as Map?) ?? const <String, dynamic>{},
          ),
          if (manifest['instructions'] case final String instructions
              when instructions.trim().isNotEmpty)
            'instructions': instructions,
        },
      ),
      options: options,
      deadlineAt: _parseDate(manifest['deadlineAt'] as String?),
      createdAt: _parseDate(manifest['createdAt'] as String?),
    );
  }

  DateTime? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }

    return DateTime.tryParse(raw);
  }

  void _enforceServerExecutionGrant(WorkerAssignment assignment) {
    final serverPlan = assignment.executionPlan;
    if (serverPlan == null) {
      return;
    }
    final v1Type = TaskTypeMapper.toV1(assignment.taskType);
    if (v1Type == null) {
      return;
    }
    final localPlan = ExecutionPlanCatalog.forTaskType(v1Type);
    final localHash = sha256
        .convert(
          utf8.encode('${localPlan.taskType}:${localPlan.stages.length}'),
        )
        .toString();
    final serverHash = serverPlan['planHash'] as String?;
    if (serverHash != null &&
        serverHash.isNotEmpty &&
        serverHash != localHash) {
      throw StateError('Server execution plan hash mismatch');
    }
    final allocation = assignment.allocation;
    if (allocation != null) {
      final maxCalls = allocation['maxInferenceCalls'];
      if (maxCalls is int && maxCalls <= 0) {
        throw StateError('Server allocation forbids inference');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Failure
  // ---------------------------------------------------------------------------

  WorkerTaskResult _failedResult(
    WorkerTaskRequest request,
    WorkerError error, {
    bool? retryable,
  }) {
    final status = error.retryable || retryable == true
        ? WorkerResultStatus.retryable
        : WorkerResultStatus.failed;

    if (error.code == WorkerErrorCode.deadlineExceeded) {
      return WorkerTaskResult(
        schemaVersion: request.schemaVersion,
        taskId: request.taskId,
        status: WorkerResultStatus.timedOut,
        error: error,
      );
    }

    if (error.code == WorkerErrorCode.cancelled) {
      return WorkerTaskResult(
        schemaVersion: request.schemaVersion,
        taskId: request.taskId,
        status: WorkerResultStatus.cancelled,
        error: error,
      );
    }

    return WorkerTaskResult(
      schemaVersion: request.schemaVersion,
      taskId: request.taskId,
      status: status,
      error: error,
    );
  }

  // ---------------------------------------------------------------------------
  // Output
  // ---------------------------------------------------------------------------

  InferenceOutput _toInferenceOutput(WorkerTaskResult result) {
    final payload = jsonEncode(result.toJson());

    return InferenceOutput(
      resultBytes: Uint8List.fromList(utf8.encode(payload)),
      progressMilli: 1000,
      metrics: {
        'outputKind': 'json',
        'taskStatus': result.status.name,
        'structuredResult': result.toJson(),
        if (result.error != null) 'errorCode': result.error!.codeName,
        ...result.metrics,
      },
    );
  }
}
