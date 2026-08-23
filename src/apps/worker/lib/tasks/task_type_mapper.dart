/// Maps public catalog task types to internal runtime capabilities.
abstract final class TaskTypeMapper {
  static const ocrExtractText = 'ocr.extract_text.v1';
  static const documentExtract = 'document.extract.v1';
  static const documentClassify = 'document.classify.v1';
  static const documentSummarize = 'document.summarize.v1';
  static const textClassify = 'text.classify.v1';
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
    documentImageQuality,
    blurryImage,
    duplicateImage,
    visionAnalyze,
    removeBackground,
  };
  static const backendToV1 = {
    'document.ocr': ocrExtractText,
    'document.extract': documentExtract,
    'text.summarize': textClassify,
    'text.classify': textClassify,
  };
  static const v1ToBackend = {
    ocrExtractText: 'document.ocr',
    documentExtract: 'document.extract',
    documentClassify: 'image.classify',
    documentSummarize: 'text.summarize',
    textClassify: 'text.classify',
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
    if (pipelineTypes.contains(type)) return type;
    final direct = backendToV1[type];
    if (direct != null) return direct;
    if (type == 'image.remove_background') return removeBackground;
    if (_visionTypes.contains(type)) return visionAnalyze;
    return _familyToV1(_pipelineFamily(type));
  }

  static String toBackend(String v1Type) => v1ToBackend[v1Type] ?? v1Type;
  static bool isPipelineTask(String type) => toV1(type) != null;
  static bool requiresOcr(String type) => const {
    ocrExtractText,
    documentExtract,
    documentClassify,
    documentSummarize,
  }.contains(type);
  static bool requiresLlm(String type, {bool ocrOnly = false}) {
    if (ocrOnly && type == ocrExtractText) return false;
    return const {
      documentExtract,
      documentClassify,
      documentSummarize,
      textClassify,
      visionAnalyze,
    }.contains(type);
  }

  static String pipelineFamily(String type) => _pipelineFamily(type);
  static String _pipelineFamily(String type) {
    if (type.startsWith('ocr.') || type == 'document.ocr')
      return 'document.ocr';
    if (type.startsWith('extract.') || type == 'document.extract')
      return 'document.extract';
    if (type == 'text.summarize') return 'text.classify';
    if (_visionTypes.contains(type)) return 'vision.analyze';
    if (type == documentImageQuality ||
        type == blurryImage ||
        type == duplicateImage)
      return type;
    if (type.startsWith('moderation.') ||
        type.startsWith('nlp.') ||
        type.startsWith('ml.') ||
        type.startsWith('dataset.') ||
        type.startsWith('review.') ||
        type.startsWith('llm.') ||
        type == 'catalog.fake_listing' ||
        type == 'text.classify')
      return 'text.classify';
    return type;
  }

  static String? _familyToV1(String family) => switch (family) {
    'document.ocr' => ocrExtractText,
    'document.extract' => documentExtract,
    'vision.analyze' => visionAnalyze,
    'text.summarize' => documentSummarize,
    'text.classify' => textClassify,
    documentImageQuality => documentImageQuality,
    blurryImage => blurryImage,
    duplicateImage => duplicateImage,
    _ => null,
  };
}
