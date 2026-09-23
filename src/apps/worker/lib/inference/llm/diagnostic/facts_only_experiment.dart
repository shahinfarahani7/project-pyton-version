import 'dart:convert';

import '../../../contracts/worker_error.dart';
import '../../../runtime/encrypted_store.dart';
import '../qwen_task_processor.dart';
import 'summarize_map_evidence_diagnostic_fixture.dart';

/// Immutable Step 1 output handed to Step 2 of the facts-only experiment.
///
/// Holds the experiment's single corrective allowance so classification cannot
/// start with a fresh one.
final class FactsOnlyExtractionSnapshot {
  FactsOnlyExtractionSnapshot({
    required this.experimentId,
    required this.extractionRunId,
    required this.fixtureId,
    required List<String> facts,
    required this.correctiveBudget,
  })  : facts = List.unmodifiable(facts),
        factsSha256 = sha256HexString(jsonEncode(facts));

  final String experimentId;
  final String extractionRunId;
  final SummarizeMapEvidenceDiagnosticFixtureId fixtureId;
  final List<String> facts;
  final String factsSha256;
  final CorrectiveInferenceBudget correctiveBudget;

  bool _classificationStarted = false;

  bool get classificationStarted => _classificationStarted;

  /// One classification per extraction; a second attempt would reuse spent state.
  void markClassificationStarted() {
    if (_classificationStarted) {
      throw WorkerError(
        code: WorkerErrorCode.invalidTask,
        message:
            'Classification already ran for extraction $extractionRunId '
            '(experiment $experimentId); run a new extraction first',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
    }
    _classificationStarted = true;
  }
}

/// Strict validator for the Step 2 diagnostic classification schema.
///
/// Index bounds are checked deterministically; whether a cited fact actually
/// supports the text is a manual check.
abstract final class FactsClassificationSchema {
  static const schemaVersion = 'diag_classify_1';

  static const _topKeys = {'schemaVersion', 'priority', 'openItems'};
  static const _entryKeys = {'text', 'supportingFactIndexes'};

  static String? validate(Map<String, dynamic> value, {required int factCount}) {
    final keys = value.keys.toSet();
    if (keys.length != _topKeys.length || !keys.containsAll(_topKeys)) {
      return 'classification_keys_invalid:keys=${keys.join(",")}';
    }
    if (value['schemaVersion'] != schemaVersion) {
      return 'classification_schema_version_invalid';
    }
    final priority = value['priority'];
    if (priority is! Map<String, dynamic>) {
      return 'classification_priority_not_object';
    }
    final priorityIssue = _validateEntry(
      priority,
      factCount: factCount,
      label: 'priority',
      allowEmpty: true,
    );
    if (priorityIssue != null) {
      return priorityIssue;
    }
    final openItems = value['openItems'];
    if (openItems is! List) {
      return 'classification_open_items_not_array';
    }
    for (var index = 0; index < openItems.length; index++) {
      final item = openItems[index];
      if (item is! Map<String, dynamic>) {
        return 'classification_open_item_not_object:index=$index';
      }
      final issue = _validateEntry(
        item,
        factCount: factCount,
        label: 'openItems[$index]',
        allowEmpty: false,
      );
      if (issue != null) {
        return issue;
      }
    }
    return null;
  }

  static String? _validateEntry(
    Map<String, dynamic> entry, {
    required int factCount,
    required String label,
    required bool allowEmpty,
  }) {
    final keys = entry.keys.toSet();
    if (keys.length != _entryKeys.length || !keys.containsAll(_entryKeys)) {
      return 'classification_entry_keys_invalid:$label';
    }
    final text = entry['text'];
    if (text is! String) {
      return 'classification_text_not_string:$label';
    }
    final indexes = entry['supportingFactIndexes'];
    if (indexes is! List) {
      return 'classification_indexes_not_array:$label';
    }
    final empty = text.trim().isEmpty;
    if (empty && !allowEmpty) {
      return 'classification_text_empty:$label';
    }
    if (empty != indexes.isEmpty) {
      return 'classification_text_index_mismatch:$label';
    }
    final seen = <int>{};
    for (final raw in indexes) {
      if (raw is! int) {
        return 'classification_index_not_integer:$label';
      }
      if (raw < 0 || raw >= factCount) {
        return 'classification_index_out_of_bounds:$label:index=$raw:factCount=$factCount';
      }
      if (!seen.add(raw)) {
        return 'classification_index_duplicated:$label:index=$raw';
      }
    }
    return null;
  }
}

/// Step 2 result; never a public task output.
final class FactsClassificationDiagnosticResult {
  const FactsClassificationDiagnosticResult({
    required this.experimentId,
    required this.extractionRunId,
    required this.classificationRunId,
    required this.fixtureId,
    required this.factsSha256,
    required this.factCount,
    required this.promptSha256,
    required this.rawResponseChars,
    required this.stopReason,
    required this.truncated,
    required this.correctiveCallsThisStep,
    required this.correctiveCallsExperimentTotal,
    required this.inferenceMs,
    this.validatedClassification,
    this.failure,
  });

  final String experimentId;
  final String extractionRunId;
  final String classificationRunId;
  final SummarizeMapEvidenceDiagnosticFixtureId fixtureId;
  final String factsSha256;
  final int factCount;
  final String promptSha256;
  final int rawResponseChars;
  final String stopReason;
  final bool truncated;
  final int correctiveCallsThisStep;
  final int correctiveCallsExperimentTotal;
  final int inferenceMs;
  final Map<String, dynamic>? validatedClassification;
  final WorkerError? failure;

  int get normalInferenceCalls => 1;

  bool get firstPassSuccess =>
      failure == null && !truncated && correctiveCallsThisStep == 0;

  bool get repairedSuccess => failure == null && correctiveCallsThisStep > 0;

  /// Index bounds are validated; entailment by the cited facts is not.
  String get semanticSupportCheck => 'manual_required';
}
