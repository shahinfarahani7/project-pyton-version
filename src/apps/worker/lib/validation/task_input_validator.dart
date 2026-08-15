import 'dart:typed_data';

import '../contracts/worker_error.dart';
import '../contracts/worker_task_request.dart';
import '../tasks/task_type_mapper.dart';

abstract final class TaskInputValidator {
  static const maxImageBytes = 10 * 1024 * 1024;
  static const maxMegapixels = 12;

  static WorkerError? validate(WorkerTaskRequest request) {
    if (request.schemaVersion.isEmpty || request.taskId.isEmpty) {
      return const WorkerError(
        code: WorkerErrorCode.invalidTask,
        message: 'Missing schemaVersion or taskId',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
    }
    if (request.isExpired) {
      return const WorkerError(
        code: WorkerErrorCode.deadlineExceeded,
        message: 'Task deadline has passed',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
    }
    if (!TaskTypeMapper.pipelineTypes.contains(request.type)) {
      return WorkerError(
        code: WorkerErrorCode.unsupportedTaskType,
        message: 'Unsupported task type: ${request.type}',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
    }

    final needsImage = TaskTypeMapper.requiresOcr(request.type);
    final needsText = request.type == TaskTypeMapper.textClassify;

    if (needsImage) {
      if (!request.input.hasImage) {
        return const WorkerError(
          code: WorkerErrorCode.invalidTask,
          message: 'Image input is required for this task type',
          retryable: false,
          stage: WorkerTaskStage.validation,
        );
      }
      final imageError = _validateImage(request.input.imageBytes!);
      if (imageError != null) {
        return imageError;
      }
    }

    if (needsText && !request.input.hasText) {
      return const WorkerError(
        code: WorkerErrorCode.invalidTask,
        message: 'Text input is required for text.classify.v1',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
    }

    if (needsImage && request.input.hasText && request.input.imageUri != null) {
      // Both provided — image takes precedence; text in manifest is metadata only.
    }

    return null;
  }

  static WorkerError? _validateImage(Uint8List bytes) {
    if (bytes.isEmpty) {
      return const WorkerError(
        code: WorkerErrorCode.imageDecodeFailed,
        message: 'Image payload is empty',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
    }
    if (bytes.length > maxImageBytes) {
      return const WorkerError(
        code: WorkerErrorCode.imageTooLarge,
        message: 'Image exceeds 10 MB limit',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
    }
    if (!_looksLikeImage(bytes)) {
      return const WorkerError(
        code: WorkerErrorCode.imageDecodeFailed,
        message: 'Unsupported or corrupt image format',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
    }
    return null;
  }

  static bool _looksLikeImage(Uint8List bytes) {
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true;
    }
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return true;
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return true;
    }
    return false;
  }
}
