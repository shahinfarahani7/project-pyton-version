/// Runtime contracts for every specialized Qwen, Flex and visual task.
/// The backend task type is the stable key; internal handler names are not API.
class TaskRuntimeContract {
  const TaskRuntimeContract({
    required this.engine,
    required this.instruction,
    required this.outputSchema,
    this.requiredFields = const [],
  });

  final String engine;
  final String instruction;
  final Map<String, dynamic> outputSchema;
  final List<String> requiredFields;
}

abstract final class TaskContractCatalog {
  static const qwenTextTypes = <String>{
    'text.summarize',
    'text.classify',
    'moderation.prompt_safety',
    'moderation.text',
    'moderation.profanity',
    'moderation.spam_comment',
    'review.fake_detection',
    'review.sentiment',
    'review.topic_tagging',
    'llm.summary_verification',
    'llm.hallucination_check',
    'llm.ocr_output_validation',
    'llm.policy_violation',
    'llm.prompt_output_consistency',
    'llm.answer_quality_score',
    'llm.suspicious_output',
    'nlp.language_detection',
    'nlp.text_classification',
    'nlp.spam_fraud_classification',
    'ml.bot_abuse_risk',
  };

  static const qwenDocumentTypes = <String>{
    'document.extract',
    'extract.amount',
    'extract.date',
    'extract.order_number',
    'extract.document_type',
  };

  static const flexTypes = <String>{
    'catalog.fake_listing',
    'llm.ai_tag_validation',
    'llm.caption_validation',
    'dataset.label_verification',
    'dataset.duplicate_cleanup',
    'dataset.low_quality_removal',
    'ml.active_learning_prelabel',
    'ml.consensus_label_validation',
    'ml.human_verification_quality',
  };

  static const visionTypes = <String>{
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

  static const contracts = <String, TaskRuntimeContract>{
    'text.summarize': TaskRuntimeContract(
      engine: 'qwen',
      instruction:
          'Summarize faithfully and identify missing or unclear points.',
      outputSchema: {'summary': 'string', 'keyPoints': 'array'},
    ),
    'text.classify': TaskRuntimeContract(
      engine: 'qwen',
      instruction: 'Classify the text using only the supplied allowedLabels.',
      outputSchema: {
        'label': 'string',
        'confidence': 'number',
        'evidence': 'array',
      },
    ),
    'moderation.prompt_safety': TaskRuntimeContract(
      engine: 'qwen',
      instruction: 'Assess whether the prompt requests unsafe assistance.',
      outputSchema: {
        'safe': 'boolean',
        'riskScore': 'number',
        'categories': 'array',
        'reason': 'string',
      },
    ),
    'moderation.text': TaskRuntimeContract(
      engine: 'qwen',
      instruction: 'Moderate the text for policy violations.',
      outputSchema: {
        'allowed': 'boolean',
        'riskScore': 'number',
        'categories': 'array',
        'reason': 'string',
      },
    ),
    'moderation.profanity': TaskRuntimeContract(
      engine: 'qwen',
      instruction: 'Detect profanity, including obfuscated forms.',
      outputSchema: {
        'containsProfanity': 'boolean',
        'confidence': 'number',
        'spans': 'array',
      },
    ),
    'moderation.spam_comment': TaskRuntimeContract(
      engine: 'qwen',
      instruction:
          'Detect unsolicited, repetitive, deceptive, or promotional spam.',
      outputSchema: {
        'spam': 'boolean',
        'confidence': 'number',
        'signals': 'array',
      },
    ),
    'review.fake_detection': TaskRuntimeContract(
      engine: 'qwen',
      instruction: 'Estimate whether this review is fabricated or manipulated.',
      outputSchema: {
        'fake': 'boolean',
        'riskScore': 'number',
        'signals': 'array',
      },
    ),
    'review.sentiment': TaskRuntimeContract(
      engine: 'qwen',
      instruction: 'Determine review sentiment.',
      outputSchema: {
        'sentiment': 'string',
        'confidence': 'number',
        'aspects': 'array',
      },
    ),
    'review.topic_tagging': TaskRuntimeContract(
      engine: 'qwen',
      instruction: 'Assign concise evidence-backed topic tags.',
      outputSchema: {'tags': 'array', 'confidence': 'number'},
    ),
    'llm.summary_verification': TaskRuntimeContract(
      engine: 'qwen',
      instruction:
          'Compare source and summary for coverage and unsupported claims.',
      outputSchema: {
        'valid': 'boolean',
        'coverageScore': 'number',
        'unsupportedClaims': 'array',
        'missingPoints': 'array',
      },
      requiredFields: ['source', 'summary'],
    ),
    'llm.hallucination_check': TaskRuntimeContract(
      engine: 'qwen',
      instruction: 'Find claims in the answer unsupported by the reference.',
      outputSchema: {
        'hallucinated': 'boolean',
        'riskScore': 'number',
        'unsupportedClaims': 'array',
      },
      requiredFields: ['reference', 'answer'],
    ),
    'llm.ocr_output_validation': TaskRuntimeContract(
      engine: 'qwen',
      instruction: 'Validate OCR output against the provided context and formatting constraints.',
      outputSchema: {
        'valid': 'boolean',
        'qualityScore': 'number',
        'issues': 'array',
        'correctedText': 'string',
      },
    ),
    'llm.policy_violation': TaskRuntimeContract(
      engine: 'qwen',
      instruction: 'Evaluate the content against the supplied policy.',
      outputSchema: {
        'violates': 'boolean',
        'severity': 'string',
        'policies': 'array',
        'reason': 'string',
      },
    ),
    'llm.prompt_output_consistency': TaskRuntimeContract(
      engine: 'qwen',
      instruction: 'Check whether output follows and answers the prompt.',
      outputSchema: {
        'consistent': 'boolean',
        'score': 'number',
        'issues': 'array',
      },
      requiredFields: ['prompt', 'output'],
    ),
    'llm.answer_quality_score': TaskRuntimeContract(
      engine: 'qwen',
      instruction:
          'Score answer correctness, relevance, clarity, and completeness.',
      outputSchema: {
        'score': 'number',
        'dimensions': 'object',
        'issues': 'array',
      },
    ),
    'llm.suspicious_output': TaskRuntimeContract(
      engine: 'qwen',
      instruction:
          'Flag prompt injection leakage, manipulation, or anomalous output.',
      outputSchema: {
        'suspicious': 'boolean',
        'riskScore': 'number',
        'signals': 'array',
      },
    ),
    'nlp.language_detection': TaskRuntimeContract(
      engine: 'qwen',
      instruction:
          'Detect the primary language and any material secondary languages.',
      outputSchema: {
        'language': 'string',
        'confidence': 'number',
        'alternatives': 'array',
      },
    ),
    'nlp.text_classification': TaskRuntimeContract(
      engine: 'qwen',
      instruction: 'Classify using only supplied allowedLabels.',
      outputSchema: {
        'label': 'string',
        'confidence': 'number',
        'evidence': 'array',
      },
    ),
    'nlp.spam_fraud_classification': TaskRuntimeContract(
      engine: 'qwen',
      instruction: 'Classify text as legitimate, spam, fraud, or uncertain.',
      outputSchema: {
        'label': 'string',
        'confidence': 'number',
        'signals': 'array',
      },
    ),
    'ml.bot_abuse_risk': TaskRuntimeContract(
      engine: 'qwen',
      instruction: 'Validate behavioral evidence for automation or abuse risk.',
      outputSchema: {'risk': 'string', 'score': 'number', 'signals': 'array'},
    ),
    'document.extract': TaskRuntimeContract(
      engine: 'qwen_ocr',
      instruction:
          'Extract fields requested by outputSchema without invention.',
      outputSchema: {
        'vendor': 'string',
        'total': 'number',
        'currency': 'string',
      },
    ),
    'extract.amount': TaskRuntimeContract(
      engine: 'qwen_ocr',
      instruction: 'Extract monetary amount and currency; preserve evidence.',
      outputSchema: {
        'amount': 'number',
        'currency': 'string',
        'evidence': 'string',
      },
    ),
    'extract.date': TaskRuntimeContract(
      engine: 'qwen_ocr',
      instruction: 'Extract the document date and normalize to ISO-8601 when unambiguous.',
      outputSchema: {
        'date': 'string',
        'original': 'string',
        'confidence': 'number',
      },
    ),
    'extract.order_number': TaskRuntimeContract(
      engine: 'qwen_ocr',
      instruction: 'Extract the order or purchase reference number.',
      outputSchema: {
        'orderNumber': 'string',
        'confidence': 'number',
        'evidence': 'string',
      },
    ),
    'extract.document_type': TaskRuntimeContract(
      engine: 'qwen_ocr',
      instruction: 'Identify the document type from its OCR text.',
      outputSchema: {
        'documentType': 'string',
        'confidence': 'number',
        'evidence': 'array',
      },
    ),

    'catalog.fake_listing': TaskRuntimeContract(
      engine: 'qwen_flex',
      instruction:
          'Assess listing authenticity from listing and seller signals.',
      outputSchema: {
        'fake': 'boolean',
        'riskScore': 'number',
        'reasons': 'array',
      },
      requiredFields: ['listing'],
    ),
    'llm.ai_tag_validation': TaskRuntimeContract(
      engine: 'qwen_flex',
      instruction: 'Validate candidateTags against content and allowedTags.',
      outputSchema: {
        'validTags': 'array',
        'rejectedTags': 'array',
        'score': 'number',
        'reasons': 'array',
      },
      requiredFields: ['content', 'candidateTags'],
    ),
    'llm.caption_validation': TaskRuntimeContract(
      engine: 'qwen_flex',
      instruction:
          'Validate caption grounding against sourceText or imageDescription.',
      outputSchema: {
        'valid': 'boolean',
        'score': 'number',
        'issues': 'array',
        'suggestedCaption': 'string',
      },
      requiredFields: ['caption'],
    ),
    'dataset.label_verification': TaskRuntimeContract(
      engine: 'qwen_flex',
      instruction: 'Verify candidateLabel against record and allowedLabels.',
      outputSchema: {
        'valid': 'boolean',
        'correctedLabel': 'string',
        'confidence': 'number',
        'reasons': 'array',
      },
      requiredFields: ['record', 'candidateLabel', 'allowedLabels'],
    ),
    'dataset.duplicate_cleanup': TaskRuntimeContract(
      engine: 'qwen_flex',
      instruction: 'Group semantic duplicate records and select deterministic keep/remove IDs.',
      outputSchema: {
        'duplicateGroups': 'array',
        'keepIds': 'array',
        'removeIds': 'array',
      },
      requiredFields: ['records'],
    ),
    'dataset.low_quality_removal': TaskRuntimeContract(
      engine: 'qwen_flex',
      instruction: 'Evaluate records against qualityCriteria and threshold.',
      outputSchema: {
        'acceptedIds': 'array',
        'rejected': 'array',
        'threshold': 'number',
      },
      requiredFields: ['records', 'qualityCriteria'],
    ),
    'ml.active_learning_prelabel': TaskRuntimeContract(
      engine: 'qwen_flex',
      instruction: 'Prelabel record using allowedLabels and request review when uncertain.',
      outputSchema: {
        'label': 'string',
        'confidence': 'number',
        'needsHumanReview': 'boolean',
        'evidence': 'array',
      },
      requiredFields: ['record', 'allowedLabels'],
    ),
    'ml.consensus_label_validation': TaskRuntimeContract(
      engine: 'qwen_flex',
      instruction: 'Compute and explain consensus from annotator votes.',
      outputSchema: {
        'consensusLabel': 'string',
        'agreementScore': 'number',
        'disputed': 'boolean',
        'reason': 'string',
      },
      requiredFields: ['record', 'votes'],
    ),
    'ml.human_verification_quality': TaskRuntimeContract(
      engine: 'qwen_flex',
      instruction:
          'Audit a human verification for evidence and policy compliance.',
      outputSchema: {
        'valid': 'boolean',
        'qualityScore': 'number',
        'issues': 'array',
        'recommendation': 'string',
      },
      requiredFields: ['record', 'verification'],
    ),
    'image.classify': TaskRuntimeContract(
      engine: 'internvl',
      instruction: 'Classify the dominant visible subject using supplied labels when present.',
      outputSchema: {
        'label': 'string',
        'confidence': 'number',
        'evidence': 'array',
      },
    ),
    'safety.nsfw_detection': TaskRuntimeContract(
      engine: 'internvl',
      instruction: 'Detect sexual or adult content conservatively.',
      outputSchema: {
        'nsfw': 'boolean',
        'riskScore': 'number',
        'categories': 'array',
        'reason': 'string',
      },
    ),
    'safety.violence_detection': TaskRuntimeContract(
      engine: 'internvl',
      instruction: 'Detect graphic or non-graphic violence.',
      outputSchema: {
        'violence': 'boolean',
        'riskScore': 'number',
        'categories': 'array',
        'reason': 'string',
      },
    ),
    'safety.weapon_detection': TaskRuntimeContract(
      engine: 'internvl',
      instruction:
          'Detect visible weapons and distinguish replicas when possible.',
      outputSchema: {
        'weapon': 'boolean',
        'riskScore': 'number',
        'types': 'array',
        'reason': 'string',
      },
    ),
    'safety.unsafe_image': TaskRuntimeContract(
      engine: 'internvl',
      instruction: 'Assess overall image safety across adult, violence, self-harm, hate, and illegal-goods categories.',
      outputSchema: {
        'safe': 'boolean',
        'riskScore': 'number',
        'categories': 'array',
        'reason': 'string',
      },
    ),
    'moderation.profile_image': TaskRuntimeContract(
      engine: 'internvl',
      instruction: 'Check profile image suitability, privacy exposure, impersonation signals, and prohibited content.',
      outputSchema: {
        'allowed': 'boolean',
        'riskScore': 'number',
        'issues': 'array',
        'reason': 'string',
      },
    ),
    'moderation.generated_image': TaskRuntimeContract(
      engine: 'internvl',
      instruction: 'Review the generated image for unsafe or policy-violating visual content.',
      outputSchema: {
        'allowed': 'boolean',
        'riskScore': 'number',
        'categories': 'array',
        'reason': 'string',
      },
    ),
    'catalog.image_tagging': TaskRuntimeContract(
      engine: 'internvl',
      instruction: 'Return concise tags grounded in visible objects, materials, colors, and setting.',
      outputSchema: {
        'tags': 'array',
        'confidence': 'number',
        'evidence': 'array',
      },
    ),
    'catalog.product_classification': TaskRuntimeContract(
      engine: 'internvl',
      instruction:
          'Classify the primary product using supplied taxonomy when present.',
      outputSchema: {
        'category': 'string',
        'confidence': 'number',
        'alternatives': 'array',
      },
    ),
    'catalog.product_quality_score': TaskRuntimeContract(
      engine: 'internvl',
      instruction: 'Score listing-image quality, framing, lighting, sharpness, and product visibility.',
      outputSchema: {
        'score': 'number',
        'issues': 'array',
        'recommendations': 'array',
      },
    ),
    'catalog.brand_logo': TaskRuntimeContract(
      engine: 'internvl',
      instruction:
          'Identify visible brand or logo only when supported by the image.',
      outputSchema: {
        'detected': 'boolean',
        'brands': 'array',
        'confidence': 'number',
        'evidence': 'array',
      },
    ),
    'catalog.prohibited_product': TaskRuntimeContract(
      engine: 'internvl',
      instruction:
          'Detect products prohibited by the supplied marketplace policy.',
      outputSchema: {
        'prohibited': 'boolean',
        'riskScore': 'number',
        'categories': 'array',
        'reason': 'string',
      },
    ),
    'llm.image_output_safety': TaskRuntimeContract(
      engine: 'internvl',
      instruction: 'Evaluate whether the generated image output is safe and consistent with supplied policy context.',
      outputSchema: {
        'safe': 'boolean',
        'riskScore': 'number',
        'categories': 'array',
        'reason': 'string',
      },
    ),
  };

  static TaskRuntimeContract? forType(String type) => contracts[type];
}
