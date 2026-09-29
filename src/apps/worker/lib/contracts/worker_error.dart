enum WorkerErrorCode {
  invalidTask,
  unsupportedTaskType,
  modelNotAvailable,
  imageTooLarge,
  imageDecodeFailed,
  ocrNoText,
  ocrLowConfidence,
  llmInvalidJson,
  outputSchemaMismatch,
  deadlineExceeded,
  cancelled,
  outOfMemoryRisk,
  visionRuntimeNotReady,
  internalError,
}

enum WorkerTaskStage { validation, ocr, llm, submit }

enum WorkerResultStatus {
  succeeded,
  rejected,
  failed,
  retryable,
  cancelled,
  timedOut,
}

class WorkerError {
  const WorkerError({
    required this.code,
    required this.message,
    required this.retryable,
    required this.stage,
  });

  final WorkerErrorCode code;
  final String message;
  final bool retryable;
  final WorkerTaskStage stage;

  factory WorkerError.fromJson(
    Map<String, dynamic>? json, {
    required String fallbackMessage,
    required bool fallbackRetryable,
  }) {
    final codeName = json?['code'] as String?;
    final stageName = (json?['stage'] as String?)?.toLowerCase();
    return WorkerError(
      code: switch (codeName) {
        'INVALID_TASK' => WorkerErrorCode.invalidTask,
        'UNSUPPORTED_TASK_TYPE' => WorkerErrorCode.unsupportedTaskType,
        'MODEL_NOT_AVAILABLE' => WorkerErrorCode.modelNotAvailable,
        'IMAGE_TOO_LARGE' => WorkerErrorCode.imageTooLarge,
        'IMAGE_DECODE_FAILED' => WorkerErrorCode.imageDecodeFailed,
        'OCR_NO_TEXT' => WorkerErrorCode.ocrNoText,
        'OCR_LOW_CONFIDENCE' => WorkerErrorCode.ocrLowConfidence,
        'LLM_INVALID_JSON' => WorkerErrorCode.llmInvalidJson,
        'OUTPUT_SCHEMA_MISMATCH' => WorkerErrorCode.outputSchemaMismatch,
        'DEADLINE_EXCEEDED' => WorkerErrorCode.deadlineExceeded,
        'CANCELLED' => WorkerErrorCode.cancelled,
        'OUT_OF_MEMORY_RISK' => WorkerErrorCode.outOfMemoryRisk,
        'VISION_RUNTIME_NOT_READY' => WorkerErrorCode.visionRuntimeNotReady,
        _ => WorkerErrorCode.internalError,
      },
      message: json?['message'] as String? ?? fallbackMessage,
      retryable: json?['retryable'] as bool? ?? fallbackRetryable,
      stage: switch (stageName) {
        'validation' => WorkerTaskStage.validation,
        'ocr' => WorkerTaskStage.ocr,
        'submit' => WorkerTaskStage.submit,
        _ => WorkerTaskStage.llm,
      },
    );
  }

  String get codeName => switch (code) {
    WorkerErrorCode.invalidTask => 'INVALID_TASK',
    WorkerErrorCode.unsupportedTaskType => 'UNSUPPORTED_TASK_TYPE',
    WorkerErrorCode.modelNotAvailable => 'MODEL_NOT_AVAILABLE',
    WorkerErrorCode.imageTooLarge => 'IMAGE_TOO_LARGE',
    WorkerErrorCode.imageDecodeFailed => 'IMAGE_DECODE_FAILED',
    WorkerErrorCode.ocrNoText => 'OCR_NO_TEXT',
    WorkerErrorCode.ocrLowConfidence => 'OCR_LOW_CONFIDENCE',
    WorkerErrorCode.llmInvalidJson => 'LLM_INVALID_JSON',
    WorkerErrorCode.outputSchemaMismatch => 'OUTPUT_SCHEMA_MISMATCH',
    WorkerErrorCode.deadlineExceeded => 'DEADLINE_EXCEEDED',
    WorkerErrorCode.cancelled => 'CANCELLED',
    WorkerErrorCode.outOfMemoryRisk => 'OUT_OF_MEMORY_RISK',
    WorkerErrorCode.visionRuntimeNotReady => 'VISION_RUNTIME_NOT_READY',
    WorkerErrorCode.internalError => 'INTERNAL_ERROR',
  };

  Map<String, dynamic> toJson() => {
    'code': codeName,
    'message': message,
    'retryable': retryable,
    'stage': stage.name.toUpperCase(),
  };

  @override
  String toString() =>
      'WorkerError(code=$codeName, retryable=$retryable, '
      'stage=${stage.name}, message=$message)';
}
