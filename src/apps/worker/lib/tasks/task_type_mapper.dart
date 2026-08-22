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

  static const _textModerationTypes = {
    'moderation.prompt_safety',
    'moderation.text',
    'moderation.profanity',
    'moderation.spam_comment',
  };

  static const _summarizeTypes = {
    'text.summarize',
    'llm.summary_verification',
  };

  static String? toV1(String backendTaskType) {
    if (pipelineTypes.contains(backendTaskType)) {
      return backendTaskType;
    }
    final direct = backendToV1[backendTaskType];
    if (direct != null) {
      return direct;
    }
    if (backendTaskType == 'image.remove_background') {
      return null;
    }
    return _familyToV1(_pipelineFamily(backendTaskType));
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

  /// Canonical backend family used for dev sample inputs and options.
  static String pipelineFamily(String backendTaskType) {
    return _pipelineFamily(backendTaskType);
  }

  static String _pipelineFamily(String backendTaskType) {
    if (backendTaskType.startsWith('ocr.') || backendTaskType == 'document.ocr') {
      return 'document.ocr';
    }
    if (backendTaskType.startsWith('extract.') || backendTaskType == 'document.extract') {
      return 'document.extract';
    }
    if (_summarizeTypes.contains(backendTaskType)) {
      return 'text.summarize';
    }
    if (_textModerationTypes.contains(backendTaskType) ||
        backendTaskType.startsWith('nlp.') ||
        backendTaskType.startsWith('ml.') ||
        backendTaskType.startsWith('dataset.') ||
        backendTaskType.startsWith('review.') ||
        backendTaskType == 'text.classify' ||
        backendTaskType.startsWith('llm.')) {
      if (backendTaskType == 'llm.summary_verification') {
        return 'text.summarize';
      }
      if (backendTaskType == 'llm.image_output_safety') {
        return 'image.classify';
      }
      return 'text.classify';
    }
    if (backendTaskType.startsWith('safety.') ||
        backendTaskType.startsWith('quality.') ||
        backendTaskType.startsWith('catalog.') ||
        backendTaskType == 'image.classify' ||
        backendTaskType.startsWith('moderation.')) {
      return 'image.classify';
    }
    return backendTaskType;
  }

  static String? _familyToV1(String family) {
    return switch (family) {
      'document.ocr' => ocrExtractText,
      'document.extract' => documentExtract,
      'image.classify' => documentClassify,
      'text.summarize' => documentSummarize,
      'text.classify' => textClassify,
      _ => null,
    };
  }
}
