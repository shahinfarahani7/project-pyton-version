/// Reads a summary written as plain labelled lines instead of JSON.
///
/// A 0.5B model breaks JSON syntax a different way every run, and asking it to
/// repair its own broken JSON only corrupts the text further. Labelled lines
/// carry the same five fields with no syntax for the model to get wrong, so
/// this is the last step before a summarize task fails closed.
abstract final class LabeledSummaryParser {
  /// Labels are matched wherever they appear, not only at the start of a line:
  /// the model bullets them, numbers them (`POINT 2:`) and sometimes puts the
  /// whole answer on one line. The value of a label runs until the next label
  /// or the end of the text.
  static final _label = RegExp(
    r'(SUMMARY|POINT|COMPLAINT|IMPROVEMENT|MISSING)[ \t]*\d*[ \t]*[:\-]',
    caseSensitive: false,
  );

  /// Returns the five summary fields, or null when the reply carries neither a
  /// summary nor a single point.
  static Map<String, dynamic>? parse(String raw) {
    if (raw.trim().isEmpty) {
      return null;
    }
    final summaryParts = <String>[];
    final keyPoints = <String>[];
    final missing = <String>[];
    var complaint = '';
    var improvement = '';

    final matches = _label.allMatches(raw).toList();
    for (var index = 0; index < matches.length; index++) {
      final match = matches[index];
      final label = match.group(1)!.toUpperCase();
      final valueEnd = index + 1 < matches.length
          ? matches[index + 1].start
          : raw.length;
      final value = _clean(raw.substring(match.end, valueEnd));
      if (value.isEmpty || _isPlaceholder(value)) {
        continue;
      }
      switch (label) {
        case 'SUMMARY':
          summaryParts.add(value);
        case 'POINT':
          keyPoints.add(value);
        case 'COMPLAINT':
          complaint = complaint.isEmpty ? value : complaint;
        case 'IMPROVEMENT':
          improvement = improvement.isEmpty ? value : improvement;
        case 'MISSING':
          missing.add(value);
      }
    }

    if (summaryParts.isEmpty && keyPoints.isEmpty) {
      return null;
    }
    return {
      'summary': summaryParts.join(' '),
      'keyPoints': keyPoints,
      'mainComplaint': complaint,
      'suggestedImprovement': improvement,
      'missingOrUnclear': missing,
    };
  }

  static String _clean(String value) {
    var text = value.replaceAll('```', ' ').trim();
    // Models often wrap the value in the quotes or bullets they saw in the
    // instruction line. A trailing marker belongs to the next label, since a
    // value runs up to where that label starts.
    text = text
        .replaceFirst(RegExp(r'^[-*\u2022]\s*'), '')
        .replaceFirst(RegExp(r'[-*\u2022\s]+$'), '');
    if (text.length > 1 && text.startsWith('"') && text.endsWith('"')) {
      text = text.substring(1, text.length - 1);
    }
    text = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    // The model likes to append its own opinion after the fact it was asked
    // for; the first two sentences are the answer.
    final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
    if (sentences.length > 2) {
      text = sentences.take(2).join(' ');
    }
    return text;
  }

  /// Values the model echoed from the instruction block, or its way of saying
  /// the field is empty.
  static bool _isPlaceholder(String value) {
    final lower = value.toLowerCase().replaceAll(RegExp(r'[.\s]+$'), '');
    return lower == '...' ||
        lower == 'none' ||
        lower == 'n/a' ||
        lower == 'nothing' ||
        lower == 'one fact' ||
        lower == 'the main complaint' ||
        lower == 'one practical action' ||
        lower.startsWith('one or two sentences');
  }
}
