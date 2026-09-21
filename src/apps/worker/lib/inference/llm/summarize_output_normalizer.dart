/// Lossless, non-semantic normalization for summarize JSON output.
class SummarizeNormalizationResult {
  const SummarizeNormalizationResult({
    required this.raw,
    required this.normalized,
  });

  final Map<String, dynamic> raw;
  final Map<String, dynamic> normalized;
}

abstract final class SummarizeOutputNormalizer {
  static SummarizeNormalizationResult normalize(Map<String, dynamic> raw) {
    return SummarizeNormalizationResult(
      raw: Map<String, dynamic>.from(raw),
      normalized: {
        'summary': _normalizeScalar(raw['summary']),
        'keyPoints': _normalizeStringList(raw['keyPoints']),
        'mainComplaint': _normalizeScalar(raw['mainComplaint']),
        'suggestedImprovement': _normalizeScalar(raw['suggestedImprovement']),
        'missingOrUnclear': _normalizeStringList(raw['missingOrUnclear']),
      },
    );
  }

  static Object? _normalizeScalar(Object? value) {
    if (value is! String) {
      return value;
    }
    return _normalizeWhitespace(value);
  }

  static Object? _normalizeStringList(Object? value) {
    if (value is! List) {
      return value;
    }
    final seen = <String>{};
    final result = <Object?>[];
    for (final item in value) {
      if (item is! String) {
        result.add(item);
        continue;
      }
      final cleaned = _normalizeWhitespace(item);
      if (cleaned.isEmpty) {
        continue;
      }
      final key = _comparisonKey(cleaned);
      if (!seen.add(key)) {
        continue;
      }
      result.add(cleaned);
    }
    return result;
  }

  static String _normalizeWhitespace(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String _comparisonKey(String value) => value.toLowerCase();
}
