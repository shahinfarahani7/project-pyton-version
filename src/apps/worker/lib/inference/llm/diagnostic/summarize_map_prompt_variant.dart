import '../../../contracts/worker_error.dart';

/// Evidence-v2 Map field-guidance variant for the isolated Map diagnostic only.
enum SummarizeMapPromptVariant {
  /// Production evidence-v2 Map wording.
  current,

  /// Experimental wording for explicit updates, attribution and field roles.
  explicitUpdates,

  /// [explicitUpdates] with the field-name mapping bullet replaced.
  explicitUpdatesNoFieldMapping,

  /// Facts-only extraction (Step 1 of the facts-only experiment); classification
  /// is a separate diagnostic call.
  factsOnly,
}

extension SummarizeMapPromptVariantLabels on SummarizeMapPromptVariant {
  String get logLabel => switch (this) {
        SummarizeMapPromptVariant.current => 'current',
        SummarizeMapPromptVariant.explicitUpdates => 'explicit_updates',
        SummarizeMapPromptVariant.explicitUpdatesNoFieldMapping =>
          'explicit_updates_no_field_mapping',
        SummarizeMapPromptVariant.factsOnly => 'facts_only',
      };
}

const summarizeMapPromptVariantConfigurationName =
    'SUMMARIZE_DIAGNOSTIC_MAP_PROMPT_VARIANT';

SummarizeMapPromptVariant parseSummarizeMapPromptVariant(String raw) {
  switch (raw.trim()) {
    case 'current':
      return SummarizeMapPromptVariant.current;
    case 'explicit_updates':
      return SummarizeMapPromptVariant.explicitUpdates;
    case 'explicit_updates_no_field_mapping':
      return SummarizeMapPromptVariant.explicitUpdatesNoFieldMapping;
    case 'facts_only':
      return SummarizeMapPromptVariant.factsOnly;
    default:
      throw WorkerError(
        code: WorkerErrorCode.invalidTask,
        message:
            'Invalid $summarizeMapPromptVariantConfigurationName="$raw"; '
            'use current, explicit_updates, explicit_updates_no_field_mapping '
            'or facts_only',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
  }
}
