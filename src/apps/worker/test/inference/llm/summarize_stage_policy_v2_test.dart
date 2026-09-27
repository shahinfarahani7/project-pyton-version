import 'package:edgemint_worker/inference/llm/summarize_evidence_pipeline.dart';
import 'package:edgemint_worker/inference/llm/summarize_inference_stage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SummarizeStagePolicy evidence schema routing', () {
    test('mapEvidence and intermediateEvidence follow SUMMARIZE_EVIDENCE_V2 flag',
        () {
      final mapPolicy =
          SummarizeStagePolicy.forStage(SummarizeInferenceStage.mapEvidence);
      final intermediatePolicy = SummarizeStagePolicy.forStage(
        SummarizeInferenceStage.intermediateEvidence,
      );
      final directPolicy =
          SummarizeStagePolicy.forStage(SummarizeInferenceStage.directPublic);

      expect(mapPolicy.usesEvidenceSchema, SummarizeEvidencePipeline.enabled);
      expect(
        intermediatePolicy.usesEvidenceSchema,
        SummarizeEvidencePipeline.enabled,
      );
      expect(directPolicy.usesEvidenceSchema, isFalse);
      expect(mapPolicy.allowSalvage, isFalse);
    });
  });
}
