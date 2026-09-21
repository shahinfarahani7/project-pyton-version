/// Versioned machine-readable constraints for `text.summarize` tasks.
///
/// [coverageAxes] and [billingRules] are rendered in prompts for the model.
/// Their semantics are **not** blocking-validated in the worker (unchecked).
abstract final class SummarizeTaskConstraints {
  static const supportedSchemaVersion = '1';

  static const supportedBillingRuleIds = {
    'pending_not_confirmed_charge',
    'promised_not_completed_refund',
  };

  static SummarizeTaskConstraintsV1? parseOptionsMap(
    Map<String, dynamic>? json,
  ) {
    if (json == null || json.isEmpty) {
      return null;
    }
    final version = json['schemaVersion']?.toString();
    if (version != supportedSchemaVersion) {
      throw SummarizeConstraintsException(
        'Unsupported summarize schemaVersion: ${version ?? "(missing)"}',
      );
    }
    return SummarizeTaskConstraintsV1.fromJson(json);
  }
}

class SummarizeConstraintsException implements Exception {
  SummarizeConstraintsException(this.message);

  final String message;

  @override
  String toString() => 'SummarizeConstraintsException: $message';
}

class SummarizeTaskConstraintsV1 {
  SummarizeTaskConstraintsV1({
    this.maxSummaryWords,
    this.keyPointCount,
    this.coverageAxes = const [],
    this.billingRules = const [],
  });

  factory SummarizeTaskConstraintsV1.fromJson(Map<String, dynamic> json) {
    final maxSummaryWords = _positiveInt(json['maxSummaryWords']);
    final keyPointCount = _positiveInt(json['keyPointCount']);

    final axesRaw = json['coverageAxes'];
    final axes = axesRaw is List
        ? axesRaw
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];

    final rulesRaw = json['billingRules'];
    final rules = <String>[];
    if (rulesRaw is List) {
      for (final item in rulesRaw) {
        final id = item.toString().trim();
        if (id.isEmpty) {
          continue;
        }
        if (!SummarizeTaskConstraints.supportedBillingRuleIds.contains(id)) {
          throw SummarizeConstraintsException('Unknown billingRules id: $id');
        }
        rules.add(id);
      }
    }

    return SummarizeTaskConstraintsV1(
      maxSummaryWords: maxSummaryWords,
      keyPointCount: keyPointCount,
      coverageAxes: axes,
      billingRules: rules,
    );
  }

  final int? maxSummaryWords;
  final int? keyPointCount;
  final List<String> coverageAxes;
  final List<String> billingRules;

  /// Billing rule IDs recognized but not semantically enforced by the worker.
  List<String> get uncheckedBillingRuleIds => billingRules;

  Map<String, dynamic> toJson() => {
    'schemaVersion': SummarizeTaskConstraints.supportedSchemaVersion,
    if (maxSummaryWords != null) 'maxSummaryWords': maxSummaryWords,
    if (keyPointCount != null) 'keyPointCount': keyPointCount,
    if (coverageAxes.isNotEmpty) 'coverageAxes': coverageAxes,
    if (billingRules.isNotEmpty) 'billingRules': billingRules,
  };

  static int? _positiveInt(Object? value) {
    if (value == null) {
      return null;
    }
    final parsed = value is int ? value : int.tryParse(value.toString());
    if (parsed == null || parsed <= 0) {
      throw SummarizeConstraintsException(
        'Expected positive integer, got $value',
      );
    }
    return parsed;
  }
}

/// Shared word-count convention with backend `count_summary_words`.
int countSummaryWords(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return 0;
  }
  return trimmed.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).length;
}

/// Returns [raw] when non-blank; blank is determined with trim only.
String? resolveSummarizeInstructions(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  return raw;
}
