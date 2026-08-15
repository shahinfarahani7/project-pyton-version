import '../../contracts/worker_task_result.dart';

abstract final class OcrTextNormalizer {
  static String normalizeLine(String input) {
    var text = input.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
    text = text.replaceAll('\u200c', '\u200c'); // preserve ZWNJ
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
    return text;
  }

  static List<OcrLineResult> normalizeLines(List<OcrLineResult> lines) {
    final normalized = <OcrLineResult>[];
    for (final line in lines) {
      final text = normalizeLine(line.text);
      if (text.isEmpty) {
        continue;
      }
      normalized.add(OcrLineResult(
        text: text,
        confidence: line.confidence,
        box: line.box,
        belowThreshold: line.belowThreshold,
      ));
    }
    normalized.sort((a, b) {
      final ay = a.box.length >= 2 ? a.box[1] : 0;
      final by = b.box.length >= 2 ? b.box[1] : 0;
      return ay.compareTo(by);
    });
    return normalized;
  }

  static String joinRawText(List<OcrLineResult> lines) {
    return lines.map((l) => l.text).join('\n');
  }

  static double averageConfidence(List<OcrLineResult> lines) {
    if (lines.isEmpty) {
      return 0;
    }
    final sum = lines.fold<double>(0, (acc, l) => acc + l.confidence);
    return sum / lines.length;
  }
}
