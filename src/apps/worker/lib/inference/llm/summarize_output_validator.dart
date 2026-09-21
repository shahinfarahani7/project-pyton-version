import 'summarize_task_constraints.dart';

class SummarizeValidationResult {
  const SummarizeValidationResult({
    required this.blockingViolations,
    this.uncheckedCoverageAxes = const [],
    this.uncheckedBillingRuleIds = const [],
  });

  final List<String> blockingViolations;
  final List<String> uncheckedCoverageAxes;
  final List<String> uncheckedBillingRuleIds;

  bool get passed => blockingViolations.isEmpty;
}

/// Deterministic structural + explicit constraint validation only.
abstract final class SummarizeOutputValidator {
  static const requiredStringFields = {
    'summary',
    'mainComplaint',
    'suggestedImprovement',
  };

  static SummarizeValidationResult validate({
    required Map<String, dynamic> summary,
    SummarizeTaskConstraintsV1? constraints,
  }) {
    final violations = <String>[];

    for (final field in requiredStringFields) {
      final value = summary[field];
      if (value is! String || value.trim().isEmpty) {
        violations.add('$field must be a non-empty string');
      }
    }

    final keyPoints = summary['keyPoints'];
    if (keyPoints is! List) {
      violations.add('keyPoints must be an array');
    } else {
      violations.addAll(_validateStringArray(
        field: 'keyPoints',
        values: keyPoints,
        requireDistinct: true,
      ));
    }

    final missing = summary['missingOrUnclear'];
    if (missing is! List) {
      violations.add('missingOrUnclear must be an array');
    } else {
      violations.addAll(_validateStringArray(
        field: 'missingOrUnclear',
        values: missing,
        requireDistinct: true,
      ));
    }

    if (constraints != null) {
      final summaryText = summary['summary'];
      if (constraints.maxSummaryWords != null && summaryText is String) {
        final words = countSummaryWords(summaryText);
        if (words > constraints.maxSummaryWords!) {
          violations.add(
            'summary exceeds maxSummaryWords '
            '(${words} > ${constraints.maxSummaryWords})',
          );
        }
      }

      if (constraints.keyPointCount != null && keyPoints is List) {
        final stringPoints = keyPoints.whereType<String>().toList();
        if (stringPoints.length != constraints.keyPointCount) {
          violations.add(
            'keyPoints count ${stringPoints.length} != '
            'keyPointCount ${constraints.keyPointCount}',
          );
        }
      }
    }

    return SummarizeValidationResult(
      blockingViolations: violations,
      uncheckedCoverageAxes: constraints?.coverageAxes ?? const [],
      uncheckedBillingRuleIds: constraints?.uncheckedBillingRuleIds ?? const [],
    );
  }

  static List<String> _validateStringArray({
    required String field,
    required List<dynamic> values,
    required bool requireDistinct,
  }) {
    final violations = <String>[];
    final seen = <String>{};
    for (var index = 0; index < values.length; index++) {
      final value = values[index];
      if (value is! String) {
        violations.add('$field[$index] must be a string');
        continue;
      }
      if (value.trim().isEmpty) {
        violations.add('$field[$index] must not be empty');
      }
      if (requireDistinct) {
        final key = value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
        if (!seen.add(key)) {
          violations.add('$field contains duplicate entries');
        }
      }
    }
    return violations;
  }
}
