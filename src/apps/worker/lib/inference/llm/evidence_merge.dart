import 'summarize_evidence_schema.dart';

/// Deterministic evidence union before optional intermediate model compression.
abstract final class EvidenceMerge {
  static Map<String, dynamic> unionPartials(
    Iterable<Map<String, dynamic>> partials,
  ) {
    final facts = <String>[];
    final openItems = <String>[];
    final priorities = <String>[];

    for (final partial in partials) {
      final normalized = SummarizeEvidenceSchema.normalize(partial);
      _appendExactUnique(facts, normalized['facts']! as List<String>);
      _appendExactUnique(openItems, normalized['openItems']! as List<String>);
      final priority = normalized['priority']! as String;
      if (priority.isNotEmpty) {
        _appendExactUnique(priorities, [priority]);
      }
    }

    return {
      'schemaVersion': SummarizeEvidenceSchema.schemaVersion,
      'facts': facts,
      'openItems': openItems,
      'priority': _joinPriorities(priorities),
    };
  }

  static void _appendExactUnique(List<String> target, List<String> items) {
    for (final item in items) {
      if (!target.contains(item)) {
        target.add(item);
      }
    }
  }

  /// Preserve distinct priority statements without inventing an ordering rule.
  static String _joinPriorities(List<String> priorities) {
    if (priorities.isEmpty) {
      return '';
    }
    if (priorities.length == 1) {
      return priorities.single;
    }
    return priorities.join(' ; ');
  }
}
