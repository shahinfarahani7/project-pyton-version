import '../../contracts/worker_error.dart';

/// Frozen evidence partial schema (Map + intermediate Reduce).
abstract final class SummarizeEvidenceSchema {
  static const schemaVersion = '2';

  static const requiredKeys = {
    'schemaVersion',
    'facts',
    'openItems',
    'priority',
  };

  static const forbiddenPublicKeys = {
    'summary',
    'keyPoints',
    'mainComplaint',
    'suggestedImprovement',
    'missingOrUnclear',
  };

  static const forbiddenProvenanceKeys = {
    'sourceChunkIndexes',
    'processedCharRanges',
  };

  /// Empty only when facts, openItems, and priority are all blank.
  static bool isEmptyPartial(Map<String, dynamic> partial) {
    final facts = partial['facts'];
    final openItems = partial['openItems'];
    final priority = partial['priority'];
    final factsEmpty = facts is List && facts.isEmpty;
    final openEmpty = openItems is List && openItems.isEmpty;
    final priorityBlank = priority is String && priority.trim().isEmpty;
    return factsEmpty && openEmpty && priorityBlank;
  }

  static bool looksLikeEvidencePartial(Map<String, dynamic> partial) =>
      partial['schemaVersion']?.toString() == schemaVersion;

  /// Returns null when valid; otherwise a rejection reason code with field/type detail.
  static String? validateStructure(Map<String, dynamic> partial) {
    if (partial['schemaVersion']?.toString() != schemaVersion) {
      return 'evidence_schema_version_mismatch';
    }
    for (final key in partial.keys) {
      if (!requiredKeys.contains(key)) {
        if (forbiddenPublicKeys.contains(key)) {
          return 'evidence_public_field_forbidden:field=$key';
        }
        if (forbiddenProvenanceKeys.contains(key)) {
          return 'evidence_provenance_field_forbidden:field=$key';
        }
        return 'evidence_unknown_field:field=$key';
      }
    }
    for (final key in requiredKeys) {
      if (!partial.containsKey(key)) {
        return 'evidence_missing_field_$key';
      }
    }
    final facts = partial['facts'];
    if (facts is! List) {
      return 'evidence_facts_not_array:type=${facts.runtimeType}';
    }
    for (var index = 0; index < facts.length; index++) {
      final item = facts[index];
      if (item is! String) {
        return 'evidence_facts_invalid_element:index=$index:type=${item.runtimeType}';
      }
      if (item.trim().isEmpty) {
        return 'evidence_facts_empty_element:index=$index';
      }
    }
    final openItems = partial['openItems'];
    if (openItems is! List) {
      return 'evidence_open_items_not_array:type=${openItems.runtimeType}';
    }
    for (var index = 0; index < openItems.length; index++) {
      final item = openItems[index];
      if (item is! String) {
        return 'evidence_open_items_invalid_element:index=$index:type=${item.runtimeType}';
      }
      if (item.trim().isEmpty) {
        return 'evidence_open_items_empty_element:index=$index';
      }
    }
    final priority = partial['priority'];
    if (priority is! String) {
      return 'evidence_priority_not_string:type=${priority.runtimeType}';
    }
    return _duplicatePriorityInFacts(partial);
  }

  static String? _duplicatePriorityInFacts(Map<String, dynamic> partial) {
    final priority = (partial['priority'] as String).trim();
    if (priority.isEmpty) {
      return null;
    }
    final normalizedPriority = priority.toLowerCase();
    final facts = partial['facts'] as List;
    for (final item in facts) {
      if (item is! String) {
        continue;
      }
      final trimmed = item.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final lower = trimmed.toLowerCase();
      if (lower == normalizedPriority ||
          lower.endsWith(': $normalizedPriority') ||
          lower.contains(normalizedPriority) &&
              lower.startsWith('customer priority')) {
        return 'evidence_priority_duplicated_in_facts';
      }
    }
    return null;
  }

  static WorkerError? validateOrError(
    Map<String, dynamic> partial, {
    required String stageLabel,
  }) {
    final reason = validateStructure(partial);
    if (reason == null) {
      return null;
    }
    return WorkerError(
      code: WorkerErrorCode.outputSchemaMismatch,
      message: 'Evidence partial invalid at $stageLabel ($reason)',
      retryable: false,
      stage: WorkerTaskStage.llm,
    );
  }

  /// Trims validated string fields only. Call [validateStructure] first.
  static Map<String, dynamic> normalize(Map<String, dynamic> partial) {
    final facts = (partial['facts'] as List)
        .cast<String>()
        .map((item) => item.trim())
        .toList(growable: false);
    final openItems = (partial['openItems'] as List)
        .cast<String>()
        .map((item) => item.trim())
        .toList(growable: false);
    return {
      'schemaVersion': schemaVersion,
      'facts': facts,
      'openItems': openItems,
      'priority': (partial['priority'] as String).trim(),
    };
  }
}
