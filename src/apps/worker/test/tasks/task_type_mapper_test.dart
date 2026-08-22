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
    expect(TaskTypeMapper.toV1('safety.nsfw_detection'), TaskTypeMapper.documentClassify);
    expect(TaskTypeMapper.toV1('ocr.receipt'), TaskTypeMapper.ocrExtractText);
    expect(TaskTypeMapper.toV1('extract.amount'), TaskTypeMapper.documentExtract);
    expect(TaskTypeMapper.toV1('moderation.profanity'), TaskTypeMapper.textClassify);
    expect(TaskTypeMapper.toV1('llm.summary_verification'), TaskTypeMapper.documentSummarize);
    expect(TaskTypeMapper.pipelineFamily('catalog.product_classification'), 'image.classify');
  });
}
