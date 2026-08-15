import 'dart:convert';
import 'dart:typed_data';

import '../api/worker_assignment_models.dart';
import '../contracts/worker_error.dart';
import '../contracts/worker_task_request.dart';
import '../contracts/worker_task_result.dart';
import '../inference/llm/qwen_task_processor.dart';
import '../inference/ocr/ocr_engine.dart';
import '../inference/ocr/ocr_models.dart';
import '../models/worker_model_catalog.dart';
import '../runtime/device_tier_policy.dart';
import '../runtime/inference_adapter.dart';
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
    required this.isImageInput,
  });

  final WorkerAssignment assignment;
  final Map<String, dynamic> manifest;
  final Uint8List inputBytes;
  final bool isImageInput;
}

class TaskExecutionEngine {
  TaskExecutionEngine({
    required OcrEngine ocrEngine,
    required QwenTaskProcessor qwenProcessor,
    MobileTaskDispatcher? dispatcher,
    IdempotencyStore? idempotencyStore,
  })  : _ocrEngine = ocrEngine,
        _qwenProcessor = qwenProcessor,
        _dispatcher = dispatcher ?? MobileTaskDispatcher(),
        _idempotency = idempotencyStore ?? IdempotencyStore();

  final OcrEngine _ocrEngine;
  final QwenTaskProcessor _qwenProcessor;
  final MobileTaskDispatcher _dispatcher;
  final IdempotencyStore _idempotency;
  WorkerTaskResult? _lastResult;
  bool _running = false;

  WorkerTaskResult? get lastResult => _lastResult;

  Future<List<String>> advertisedCapabilities({
    required bool qwenReady,
    required bool ocrReady,
  }) async {
    final caps = <String>[];
    for (final cap in _dispatcher.capabilities) {
      if (TaskTypeMapper.requiresOcr(cap) && !ocrReady) {
        continue;
      }
      if (TaskTypeMapper.requiresLlm(cap) && !qwenReady) {
        continue;
      }
      caps.add(cap);
    }
    return caps;
  }

  Future<InferenceOutput> execute({
    required TaskExecutionContext context,
    required String signingKey,
    required int freeStorageMb,
    bool Function()? isCancelled,
  }) async {
    if (_running) {
      throw StateError('Concurrent task execution is not allowed');
    }
    _running = true;
    try {
      final request = _buildRequest(context);
      final cached = _idempotency.get(request.idempotencyKey);
      if (cached != null) {
        _lastResult = cached;
        return _toInferenceOutput(cached);
      }

      final validationError = TaskInputValidator.validate(request);
      if (validationError != null) {
        final result = _failedResult(request, validationError);
        _lastResult = result;
        return _toInferenceOutput(result);
      }

      final v1Type = request.type;
      final tier = DeviceTierPolicy.fromFreeStorageMb(freeStorageMb);
      if (TaskTypeMapper.requiresOcr(v1Type) &&
          TaskTypeMapper.requiresLlm(v1Type, ocrOnly: request.options.ocrOnly) &&
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

      final handler = _dispatcher.handlerFor(v1Type);
      if (handler == null) {
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

      if (TaskTypeMapper.requiresOcr(v1Type)) {
        final ocrReady = await _ocrEngine.isReady();
        if (!ocrReady) {
          try {
            await _ocrEngine.ensureLoaded();
          } catch (_) {
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

      final metrics = WorkerTaskMetrics();
      metrics.inputBytes = context.inputBytes.length;

      try {
        if (isCancelled?.call() == true) {
          throw const WorkerError(
            code: WorkerErrorCode.cancelled,
            message: 'Task cancelled',
            retryable: false,
            stage: WorkerTaskStage.validation,
          );
        }

        final result = await handler.handle(
          request: request,
          ocrEngine: _ocrEngine,
          qwenProcessor: _qwenProcessor,
          signingKey: signingKey,
          metrics: metrics,
          isCancelled: isCancelled,
        );
        final enriched = WorkerTaskResult(
          schemaVersion: result.schemaVersion,
          taskId: result.taskId,
          status: result.status,
          output: result.output,
          metrics: {
            ...result.metrics,
            ...metrics.toJson(),
          },
          modelInfo: {
            'ocrDetector': PaddleOcrModelCatalog.detectorVersion,
            'ocrRecognizer': PaddleOcrModelCatalog.recognizerVersion,
            'llm': WorkerModelCatalog.displayName,
            'runtime': 'LiteRT/flutter_gemma',
          },
          error: result.error,
        );
        _idempotency.put(request.idempotencyKey, enriched);
        _lastResult = enriched;
        return _toInferenceOutput(enriched);
      } on WorkerError catch (error) {
        final result = _failedResult(request, error, retryable: error.retryable);
        _idempotency.put(request.idempotencyKey, result);
        _lastResult = result;
        return _toInferenceOutput(result);
      } catch (error) {
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

  WorkerTaskRequest _buildRequest(TaskExecutionContext context) {
    final manifest = context.manifest;
    final optionsJson = manifest['options'] as Map<String, dynamic>?;
    final options = WorkerTaskOptions.fromJson(optionsJson);
    final v1Type = TaskTypeMapper.toV1(context.assignment.taskType) ??
        context.assignment.taskType;
    final text = manifest['inputText'] as String? ??
        manifest['contentText'] as String? ??
        (context.isImageInput ? null : utf8.decode(context.inputBytes));
    return WorkerTaskRequest(
      schemaVersion: manifest['schemaVersion'] as String? ?? '1.0',
      taskId: context.assignment.taskId ?? context.assignment.assignmentId,
      idempotencyKey: manifest['idempotencyKey'] as String? ??
          context.assignment.attemptId,
      type: v1Type,
      input: WorkerTaskInput(
        imageBytes: context.isImageInput ? context.inputBytes : null,
        text: text,
        imageUri: manifest['imageUri'] as String?,
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
