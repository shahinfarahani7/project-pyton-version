// NOT RUN — prepared for Phase 2 evidence contract regression.
//
// Run manually when SUMMARIZE_EVIDENCE_V2 compile flag is enabled:
// flutter test test/inference/llm/phase2_evidence_contract_test.dart
//   --dart-define=SUMMARIZE_EVIDENCE_V2=true

import 'package:edgemint_worker/inference/llm/evidence_merge.dart';
import 'package:edgemint_worker/inference/llm/evidence_partial_validator.dart';
import 'package:edgemint_worker/inference/llm/summarize_evidence_schema.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/phase2_evidence_chunk2.dart';

void main() {
  group('Phase 2 evidence schema contract (NOT RUN by default)', () {
    test('accepts chunk-2 regression fixture shape', () {
      final issues = EvidencePartialValidator.validate(
        partial: phase2EvidenceChunk2,
        generationTruncated: false,
      );
      expect(issues, isEmpty);
    });

    test('empty partial requires facts, openItems, and priority all blank', () {
      expect(SummarizeEvidenceSchema.isEmptyPartial(phase2EvidenceAllEmpty), isTrue);
      expect(
        SummarizeEvidenceSchema.isEmptyPartial(phase2EvidenceOpenItemsOnly),
        isFalse,
      );
      expect(
        SummarizeEvidenceSchema.isEmptyPartial(phase2EvidencePriorityOnly),
        isFalse,
      );
      expect(
        SummarizeEvidenceSchema.isEmptyPartial({
          ...phase2EvidenceChunk2,
          'facts': <String>[],
        }),
        isFalse,
        reason: 'facts=[] alone is valid when openItems or priority carry content',
      );
    });

    test('rejects public five-field keys in evidence partial', () {
      final invalid = Map<String, dynamic>.from(phase2EvidenceChunk2)
        ..['summary'] = 'forbidden';
      final issues = EvidencePartialValidator.validate(
        partial: invalid,
        generationTruncated: false,
      );
      expect(
        issues,
        anyElement(startsWith('evidence_public_field_forbidden')),
      );
    });

    test('union merge dedupes exact strings only', () {
      final left = Map<String, dynamic>.from(phase2EvidenceChunk2);
      final firstFact = (phase2EvidenceChunk2['facts'] as List).first as String;
      final firstOpenItem =
          (phase2EvidenceChunk2['openItems'] as List).first as String;
      final right = {
        'schemaVersion': '2',
        'facts': [
          firstFact,
          'Order B410 arrived more than 40 minutes late.',
        ],
        'openItems': [firstOpenItem],
        'priority': 'late delivery',
      };
      final merged = EvidenceMerge.unionPartials([left, right]);
      expect(merged['facts'], hasLength(5));
      expect(merged['openItems'], hasLength(2));
      expect(
        (merged['priority'] as String).contains(' ; '),
        isTrue,
        reason: 'distinct priorities joined with semicolon',
      );
    });

    test('rejects truncated evidence generation', () {
      final issues = EvidencePartialValidator.validate(
        partial: phase2EvidenceChunk2,
        generationTruncated: true,
        stopReason: 'output_limit',
      );
      expect(
        issues,
        contains('evidence_partial_generation_truncated:output_limit'),
      );
    });
  });
}
