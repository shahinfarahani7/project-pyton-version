// NOT RUN — prepared for Phase 2 empty-partial policy regression.
//
// Validates empty-partial semantics without requiring SUMMARIZE_EVIDENCE_V2 at compile time.

import 'package:edgemint_worker/inference/llm/summarize_evidence_schema.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/phase2_evidence_chunk2.dart';

void main() {
  group('Phase 2 empty partial policy (NOT RUN by default)', () {
    test('does not treat facts=[] alone as empty when openItems has content', () {
      expect(
        SummarizeEvidenceSchema.isEmptyPartial(phase2EvidenceOpenItemsOnly),
        isFalse,
      );
    });

    test('does not treat facts=[] alone as empty when priority is non-blank', () {
      expect(
        SummarizeEvidenceSchema.isEmptyPartial(phase2EvidencePriorityOnly),
        isFalse,
      );
    });

    test('all three evidence fields blank defines empty partial', () {
      expect(
        SummarizeEvidenceSchema.isEmptyPartial(phase2EvidenceAllEmpty),
        isTrue,
      );
    });
  });
}
