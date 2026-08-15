import 'package:edgemint_worker/tasks/task_type_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps backend task types to v1 pipeline types', () {
    expect(TaskTypeMapper.toV1('document.ocr'), TaskTypeMapper.ocrExtractText);
    expect(TaskTypeMapper.toV1('document.extract'), TaskTypeMapper.documentExtract);
    expect(TaskTypeMapper.toV1('text.classify'), TaskTypeMapper.textClassify);
    expect(TaskTypeMapper.requiresOcr(TaskTypeMapper.textClassify), isFalse);
    expect(TaskTypeMapper.requiresLlm(TaskTypeMapper.ocrExtractText), isFalse);
    expect(TaskTypeMapper.isPipelineTask('image.classify'), isTrue);
  });
}
