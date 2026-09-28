/// Maps public catalog task types to internal runtime capabilities.
abstract final class TaskTypeMapper {
  static const ocrExtractText = 'ocr.extract_text.v1';
  static const documentExtract = 'document.extract.v1';
  static const documentClassify = 'document.classify.v1';
  static const documentSummarize = 'document.summarize.v1';
  static const textClassify = 'text.classify.v1';
  static const textSummarize = 'text.summarize.v1';
  static const textDirect = 'text.direct.v1';

  static const documentImageQuality = 'quality.document_image';
  static const blurryImage = 'quality.blurry_image';
  static const duplicateImage = 'catalog.duplicate_image';
  static const visionAnalyze = 'vision.analyze.v1';
  static const removeBackground = 'image.remove_background.v1';

  static const pipelineTypes = {
    ocrExtractText,
    documentExtract,
    documentClassify,
    documentSummarize,
    textClassify,
    textSummarize,
    textDirect,
    documentImageQuality,
    blurryImage,
    duplicateImage,
    visionAnalyze,
    removeBackground,
  };

  static const backendToV1 = {
    'document.ocr': ocrExtractText,
    'document.extract': documentExtract,
    'document.classify': documentClassify,
    'document.summarize': documentSummarize,
    'text.summarize': textSummarize,
    'text.direct': textDirect,
    'text.classify': textClassify,
  };

  static const v1ToBackend = {
    ocrExtractText: 'document.ocr',
    documentExtract: 'document.extract',
    documentClassify: 'document.classify',
    documentSummarize: 'document.summarize',
    textClassify: 'text.classify',
    textSummarize: 'text.summarize',
    textDirect: 'text.direct',
    visionAnalyze: 'image.classify',
    removeBackground: 'image.remove_background',
  };

  static const _visionTypes = {
    'image.classify',
    'safety.nsfw_detection',
    'safety.violence_detection',
    'safety.weapon_detection',
    'safety.unsafe_image',
    'moderation.profile_image',
    'moderation.generated_image',
    'catalog.image_tagging',
    'catalog.product_classification',
    'catalog.product_quality_score',
    'catalog.brand_logo',
    'catalog.prohibited_product',
    'llm.image_output_safety',
  };

  static String? toV1(String type) {
    final normalized = type.trim();
    if (normalized.isEmpty) return null;

    if (pipelineTypes.contains(normalized)) return normalized;

    final direct = backendToV1[normalized];
    if (direct != null) return direct;

    if (normalized == 'image.remove_background') return removeBackground;
    if (_visionTypes.contains(normalized)) return visionAnalyze;

    return _familyToV1(_pipelineFamily(normalized));
  }

  static String toBackend(String v1Type) => v1ToBackend[v1Type] ?? v1Type;

  static bool isPipelineTask(String type) => toV1(type) != null;

  static bool requiresOcr(String type) => const {
    ocrExtractText,
    documentExtract,
    documentClassify,
    documentSummarize,
  }.contains(type);

  static bool requiresText(String type) => const {
    textClassify,
    textSummarize,
  }.contains(type);

  static bool requiresLlm(String type, {bool ocrOnly = false}) {
    if (ocrOnly && requiresOcr(type)) return false;

    return const {
      documentExtract,
      documentClassify,
      documentSummarize,
      textClassify,
      textSummarize,
      textDirect,
      visionAnalyze,
    }.contains(type);
  }

  static String pipelineFamily(String type) => _pipelineFamily(type.trim());

  static String _pipelineFamily(String type) {
    if (type.startsWith('ocr.') || type == 'document.ocr') {
      return 'document.ocr';
    }

    if (type.startsWith('extract.') || type == 'document.extract') {
      return 'document.extract';
    }

    if (type == 'document.classify') {
      return 'document.classify';
    }

    if (type == 'document.summarize') {
      return 'document.summarize';
    }

    if (type == 'text.summarize') {
      return 'text.summarize';
    }

    if (type == 'text.direct') {
      return 'text.direct';
    }

    if (_visionTypes.contains(type)) {
      return 'vision.analyze';
    }

    if (type == documentImageQuality ||
        type == blurryImage ||
        type == duplicateImage) {
      return type;
    }

    if (type.startsWith('moderation.') ||
        type.startsWith('nlp.') ||
        type.startsWith('ml.') ||
        type.startsWith('dataset.') ||
        type.startsWith('review.') ||
        type.startsWith('llm.') ||
        type == 'catalog.fake_listing' ||
        type == 'text.classify') {
      return 'text.classify';
    }

    return type;
  }

  static String? _familyToV1(String family) => switch (family) {
    'document.ocr' => ocrExtractText,
    'document.extract' => documentExtract,
    'document.classify' => documentClassify,
    'document.summarize' => documentSummarize,
    'vision.analyze' => visionAnalyze,
    'text.summarize' => textSummarize,
    'text.direct' => textDirect,
    'text.classify' => textClassify,
    documentImageQuality => documentImageQuality,
    blurryImage => blurryImage,
    duplicateImage => duplicateImage,
    _ => null,
  };
}
