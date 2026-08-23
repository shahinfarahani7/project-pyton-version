import 'dart:typed_data';

import '../contracts/task_contract_catalog.dart';
import '../contracts/worker_error.dart';
import '../contracts/worker_task_request.dart';
import '../tasks/task_type_mapper.dart';

abstract final class TaskInputValidator {
  static const maxImageBytes = 10 * 1024 * 1024;

  static WorkerError? validate(WorkerTaskRequest request) {
    WorkerError invalid(String message) => WorkerError(
      code: WorkerErrorCode.invalidTask,
      message: message,
      retryable: false,
      stage: WorkerTaskStage.validation,
    );
    if (request.schemaVersion.isEmpty || request.taskId.isEmpty) {
      return invalid('Missing schemaVersion or taskId');
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

    final needsImage =
        TaskTypeMapper.requiresOcr(request.type) ||
        const {
          TaskTypeMapper.documentImageQuality,
          TaskTypeMapper.blurryImage,
          TaskTypeMapper.duplicateImage,
          TaskTypeMapper.visionAnalyze,
          TaskTypeMapper.removeBackground,
        }.contains(request.type);
    if (needsImage) {
      if (!request.input.hasImage)
        return invalid('Image input is required for ${request.sourceTaskType}');
      final imageError = _validateImage(
        request.input.imageBytes!,
        allowPdf: TaskTypeMapper.requiresOcr(request.type),
      );
      if (imageError != null) return imageError;
    }
    if (request.type == TaskTypeMapper.duplicateImage) {
      if (!request.input.hasCompareImage)
        return invalid(
          'Exactly two images are required for duplicate image detection',
        );
      final compareError = _validateImage(request.input.compareImageBytes!);
      if (compareError != null) return compareError;
    }

    final isFlex = TaskContractCatalog.flexTypes.contains(
      request.sourceTaskType,
    );
    if (request.type == TaskTypeMapper.textClassify &&
        !isFlex &&
        !request.input.hasText) {
      return invalid('Text input is required for ${request.sourceTaskType}');
    }
    final contract = TaskContractCatalog.forType(request.sourceTaskType);
    if (contract != null) {
      final missing = contract.requiredFields
          .where(
            (key) =>
                !request.input.data.containsKey(key) ||
                request.input.data[key] == null,
          )
          .toList();
      if (missing.isNotEmpty) {
        return invalid(
          'Missing required inputData fields for ${request.sourceTaskType}: ${missing.join(", ")}',
        );
      }
    }
    return null;
  }

  static WorkerError? _validateImage(Uint8List bytes, {bool allowPdf = false}) {
    if (bytes.isEmpty)
      return const WorkerError(
        code: WorkerErrorCode.imageDecodeFailed,
        message: 'Image payload is empty',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
    if (bytes.length > maxImageBytes)
      return const WorkerError(
        code: WorkerErrorCode.imageTooLarge,
        message: 'Image exceeds 10 MB limit',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
    if (!_looksLikeRasterImage(bytes) && !(allowPdf && _looksLikePdf(bytes)))
      return const WorkerError(
        code: WorkerErrorCode.imageDecodeFailed,
        message: 'Unsupported or corrupt image format',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
    return null;
  }

  static bool _looksLikeRasterImage(Uint8List b) =>
      b.length >= 4 &&
          b[0] == 0x89 &&
          b[1] == 0x50 &&
          b[2] == 0x4E &&
          b[3] == 0x47 ||
      b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF ||
      b.length >= 12 &&
          b[0] == 0x52 &&
          b[1] == 0x49 &&
          b[2] == 0x46 &&
          b[3] == 0x46 &&
          b[8] == 0x57 &&
          b[9] == 0x45 &&
          b[10] == 0x42 &&
          b[11] == 0x50 ||
      b.length >= 6 &&
          b[0] == 0x47 &&
          b[1] == 0x49 &&
          b[2] == 0x46 &&
          b[3] == 0x38 &&
          (b[4] == 0x37 || b[4] == 0x39) &&
          b[5] == 0x61;

  static bool _looksLikePdf(Uint8List b) =>
      b.length >= 4 &&
      b[0] == 0x25 &&
      b[1] == 0x50 &&
      b[2] == 0x44 &&
      b[3] == 0x46;
}
