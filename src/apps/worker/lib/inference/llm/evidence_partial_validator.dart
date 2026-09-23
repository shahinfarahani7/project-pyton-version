import 'summarize_evidence_schema.dart';

/// Structural validation for evidence partials at Map and intermediate Reduce.
abstract final class EvidencePartialValidator {
  static List<String> validate({
    required Map<String, dynamic> partial,
    required bool generationTruncated,
    String? stopReason,
  }) {
    final issues = <String>[];
    if (generationTruncated) {
      issues.add(
        'evidence_partial_generation_truncated:${stopReason ?? 'unknown'}',
      );
    }
    final structural = SummarizeEvidenceSchema.validateStructure(partial);
    if (structural != null) {
      issues.add(structural);
    }
    return issues;
  }
}
