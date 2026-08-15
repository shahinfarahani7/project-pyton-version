/// Maps backend assignment task types to internal v1 pipeline capabilities.
abstract final class TaskTypeMapper {
  static const ocrExtractText = 'ocr.extract_text.v1';
  static const documentExtract = 'document.extract.v1';
  static const documentClassify = 'document.classify.v1';
  static const documentSummarize = 'document.summarize.v1';
  static const textClassify = 'text.classify.v1';

  static const pipelineTypes = {
    ocrExtractText,
    documentExtract,
    documentClassify,
    documentSummarize,
    textClassify,
  };

  static const backendToV1 = {
    'document.ocr': ocrExtractText,
    'document.extract': documentExtract,
    'image.classify': documentClassify,
    'text.summarize': documentSummarize,
    'text.classify': textClassify,
  };

  static const v1ToBackend = {
    ocrExtractText: 'document.ocr',
    documentExtract: 'document.extract',
    documentClassify: 'image.classify',
    documentSummarize: 'text.summarize',
    textClassify: 'text.classify',
  };

  static String? toV1(String backendTaskType) {
    if (pipelineTypes.contains(backendTaskType)) {
      return backendTaskType;
    }
    return backendToV1[backendTaskType];
  }

  static String toBackend(String v1Type) {
    return v1ToBackend[v1Type] ?? v1Type;
  }

  static bool isPipelineTask(String backendTaskType) {
    return toV1(backendTaskType) != null;
  }

  static bool requiresOcr(String v1Type) {
    return v1Type != textClassify;
  }

  static bool requiresLlm(String v1Type, {bool ocrOnly = false}) {
    if (ocrOnly && v1Type == ocrExtractText) {
      return false;
    }
    return v1Type != ocrExtractText;
  }
}
