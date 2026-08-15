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
        WorkerErrorCode.internalError => 'INTERNAL_ERROR',
      };

  Map<String, dynamic> toJson() => {
        'code': codeName,
        'message': message,
        'retryable': retryable,
        'stage': stage.name.toUpperCase(),
      };
}
