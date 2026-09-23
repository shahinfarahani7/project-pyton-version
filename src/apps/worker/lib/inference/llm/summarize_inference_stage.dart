import 'summarize_evidence_pipeline.dart';

/// Typed inference stage for summarize JSON tasks and generic JSON tasks.
enum SummarizeInferenceStage {
  mapEvidence,
  intermediateEvidence,
  finalPublic,
  directPublic,
  constraintRepair,
  genericJson,
}

/// Per-stage parsing and recovery policy (no prompt-substring detection).
final class SummarizeStagePolicy {
  const SummarizeStagePolicy._({
    required this.allowSalvage,
    required this.allowLabeledFallback,
    required this.allowCompleteMissingFields,
    required this.allowTrimToLimits,
    required this.allowModelCompact,
    required this.usesEvidenceSchema,
    required this.rejectGenerationTruncation,
    required this.logLabel,
  });

  final bool allowSalvage;
  final bool allowLabeledFallback;
  final bool allowCompleteMissingFields;
  final bool allowTrimToLimits;
  final bool allowModelCompact;
  final bool usesEvidenceSchema;
  final bool rejectGenerationTruncation;
  final String logLabel;

  static SummarizeStagePolicy forStage(SummarizeInferenceStage stage) {
    final policy = switch (stage) {
        SummarizeInferenceStage.mapEvidence => const SummarizeStagePolicy._(
          allowSalvage: false,
          allowLabeledFallback: false,
          allowCompleteMissingFields: false,
          allowTrimToLimits: false,
          allowModelCompact: false,
          usesEvidenceSchema: true,
          rejectGenerationTruncation: true,
          logLabel: 'mapEvidence',
        ),
        SummarizeInferenceStage.intermediateEvidence =>
          const SummarizeStagePolicy._(
            allowSalvage: false,
            allowLabeledFallback: false,
            allowCompleteMissingFields: false,
            allowTrimToLimits: false,
            allowModelCompact: false,
            usesEvidenceSchema: true,
            rejectGenerationTruncation: true,
            logLabel: 'intermediateEvidence',
          ),
        SummarizeInferenceStage.finalPublic => const SummarizeStagePolicy._(
          allowSalvage: true,
          allowLabeledFallback: true,
          allowCompleteMissingFields: true,
          allowTrimToLimits: false,
          allowModelCompact: false,
          usesEvidenceSchema: false,
          rejectGenerationTruncation: false,
          logLabel: 'finalPublic',
        ),
        SummarizeInferenceStage.directPublic => const SummarizeStagePolicy._(
          allowSalvage: true,
          allowLabeledFallback: true,
          allowCompleteMissingFields: true,
          allowTrimToLimits: true,
          allowModelCompact: true,
          usesEvidenceSchema: false,
          rejectGenerationTruncation: false,
          logLabel: 'directPublic',
        ),
        SummarizeInferenceStage.constraintRepair => const SummarizeStagePolicy._(
          allowSalvage: true,
          allowLabeledFallback: false,
          allowCompleteMissingFields: false,
          allowTrimToLimits: false,
          allowModelCompact: false,
          usesEvidenceSchema: false,
          rejectGenerationTruncation: false,
          logLabel: 'constraintRepair',
        ),
        SummarizeInferenceStage.genericJson => const SummarizeStagePolicy._(
          allowSalvage: true,
          allowLabeledFallback: true,
          allowCompleteMissingFields: true,
          allowTrimToLimits: true,
          allowModelCompact: true,
          usesEvidenceSchema: false,
          rejectGenerationTruncation: false,
          logLabel: 'genericJson',
        ),
      };
    if (!SummarizeEvidencePipeline.enabled &&
        (stage == SummarizeInferenceStage.mapEvidence ||
            stage == SummarizeInferenceStage.intermediateEvidence)) {
      return SummarizeStagePolicy._(
        allowSalvage: policy.allowSalvage,
        allowLabeledFallback: policy.allowLabeledFallback,
        allowCompleteMissingFields: policy.allowCompleteMissingFields,
        allowTrimToLimits: policy.allowTrimToLimits,
        allowModelCompact: policy.allowModelCompact,
        usesEvidenceSchema: false,
        rejectGenerationTruncation: policy.rejectGenerationTruncation,
        logLabel: policy.logLabel,
      );
    }
    return policy;
  }
}
