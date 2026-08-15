import 'dart:convert';
import 'dart:typed_data';

import 'package:edgemint_worker/contracts/worker_task_request.dart';
import 'package:edgemint_worker/tasks/task_type_mapper.dart';
import 'package:edgemint_worker/validation/task_input_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );

  WorkerTaskRequest imageRequest(String type) => WorkerTaskRequest(
        schemaVersion: '1.0',
        taskId: 'tsk',
        idempotencyKey: 'key',
        type: type,
        input: WorkerTaskInput(imageBytes: Uint8List.fromList(png)),
      );

  test('rejects oversized images', () {
    final huge = Uint8List(TaskInputValidator.maxImageBytes + 1);
    huge[0] = 0x89;
    huge[1] = 0x50;
    huge[2] = 0x4E;
    huge[3] = 0x47;
    final error = TaskInputValidator.validate(
      WorkerTaskRequest(
        schemaVersion: '1.0',
        taskId: 'tsk',
        idempotencyKey: 'key',
        type: TaskTypeMapper.ocrExtractText,
        input: WorkerTaskInput(imageBytes: huge),
      ),
    );
    expect(error?.code.name, 'imageTooLarge');
  });

  test('requires text for text.classify', () {
    final error = TaskInputValidator.validate(
      WorkerTaskRequest(
        schemaVersion: '1.0',
        taskId: 'tsk',
        idempotencyKey: 'key',
        type: TaskTypeMapper.textClassify,
        input: const WorkerTaskInput(text: '  '),
      ),
    );
    expect(error, isNotNull);
  });

  test('accepts valid OCR image request', () {
    expect(TaskInputValidator.validate(imageRequest(TaskTypeMapper.ocrExtractText)), isNull);
  });
}
