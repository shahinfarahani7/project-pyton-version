/// Validates map-stage partial summaries before they enter reduce.
abstract final class MapPartialValidator {
  /// Returns blocking issue codes; empty means the partial may enter reduce.
  static List<String> validate({
    required Map<String, dynamic> partial,
    required bool generationTruncated,
    String? stopReason,
  }) {
    final issues = <String>[];
    if (generationTruncated) {
      issues.add(
        'map_partial_generation_truncated:${stopReason ?? 'unknown'}',
      );
    }

    final keyPoints = partial['keyPoints'];
    final keyPointCount = keyPoints is List
        ? keyPoints
              .whereType<String>()
              .where((point) => point.trim().isNotEmpty)
              .length
        : 0;

    final summary = partial['summary'];
    final summaryText = summary is String ? summary.trim() : '';

    // A map partial must carry at least one extracted fact. Summary-only
    // replies (common labeled-fallback failure mode) are not usable input.
    if (keyPointCount == 0) {
      issues.add('map_partial_missing_key_points');
    }

    if (summaryText.isEmpty && keyPointCount == 0) {
      issues.add('map_partial_empty');
    }

    return issues;
  }
}
