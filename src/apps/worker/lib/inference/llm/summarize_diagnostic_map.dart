import '../../contracts/worker_error.dart';
import 'diagnostic/summarize_map_evidence_diagnostic_fixture.dart';
import 'diagnostic/facts_only_experiment.dart';
import 'diagnostic/summarize_map_prompt_variant.dart';
import 'summarize_evidence_pipeline.dart';

/// Opt-in isolated Map evidence diagnostic (compile-time only).
abstract final class SummarizeDiagnosticMap {
  static const _invokeAtStartup = bool.fromEnvironment(
    'SUMMARIZE_DIAGNOSTIC_INVOKE_AT_STARTUP',
    defaultValue: false,
  );

  static const requested = bool.fromEnvironment(
    'SUMMARIZE_DIAGNOSTIC_MAP_EVIDENCE',
    defaultValue: false,
  );

  static const configurationName = 'SUMMARIZE_DIAGNOSTIC_MAP_EVIDENCE';

  static const invokeConfigurationName = 'SUMMARIZE_DIAGNOSTIC_INVOKE_AT_STARTUP';

  static const fixtureConfigurationName = 'SUMMARIZE_DIAGNOSTIC_MAP_FIXTURE';

  static const _rawFixtureSelection = String.fromEnvironment(
    fixtureConfigurationName,
    defaultValue: 'baseline',
  );

  static const _rawPromptVariant = String.fromEnvironment(
    summarizeMapPromptVariantConfigurationName,
    defaultValue: 'current',
  );

  /// Map prompt variant for the isolated diagnostic; production never reads this.
  static SummarizeMapPromptVariant get promptVariant =>
      parseSummarizeMapPromptVariant(_rawPromptVariant);

  /// Default fixture for [invokeAtStartup] only; UI passes an explicit id per run.
  static SummarizeMapEvidenceDiagnosticFixtureId get defaultFixtureId =>
      _parseFixtureId(_rawFixtureSelection);

  static SummarizeMapEvidenceDiagnosticFixtureId _parseFixtureId(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'narrative':
        return SummarizeMapEvidenceDiagnosticFixtureId.narrative;
      case 'baseline':
      case 'baseline_fact_lines':
      case '':
        return SummarizeMapEvidenceDiagnosticFixtureId.baselineFactLines;
      default:
        throw WorkerError(
          code: WorkerErrorCode.invalidTask,
          message:
              'Invalid $fixtureConfigurationName="$raw"; '
              'use baseline or narrative',
          retryable: false,
          stage: WorkerTaskStage.validation,
        );
    }
  }

  /// Feature armed: v2 evidence on and diagnostic flag set.
  static bool get armed =>
      SummarizeEvidencePipeline.enabled && requested;

  static bool get invokeAtStartup => armed && _invokeAtStartup;

  static void assertArmedOrThrow() {
    if (!SummarizeEvidencePipeline.enabled) {
      throw WorkerError(
        code: WorkerErrorCode.invalidTask,
        message:
            '$configurationName requires '
            'SUMMARIZE_EVIDENCE_V2=true',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
    }
    if (!requested) {
      throw WorkerError(
        code: WorkerErrorCode.invalidTask,
        message:
            '$configurationName is false; set '
            '--dart-define=$configurationName=true to arm the diagnostic',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
    }
  }

  static String newRunId() {
    final now = DateTime.now().toUtc();
    return 'diag_map_${now.toIso8601String().replaceAll(':', '').replaceAll('.', '')}';
  }
}

/// Result of an isolated Map evidence diagnostic run (not a public task output).
final class SummarizeMapEvidenceDiagnosticResult {
  const SummarizeMapEvidenceDiagnosticResult({
    required this.runId,
    this.experimentId,
    this.factsSnapshot,
    required this.fixtureId,
    required this.promptVariant,
    required this.promptSha256,
    required this.sourceChars,
    required this.sourceSha256,
    required this.inferenceStage,
    required this.promptChars,
    required this.rawResponseChars,
    required this.stopReason,
    required this.truncated,
    required this.normalInferenceCalls,
    required this.correctiveInferenceCalls,
    required this.inferenceMs,
    required this.firstPassSuccess,
    this.validatedEvidence,
    this.failure,
  });

  final String runId;

  /// Set for facts-only extractions; links Step 1 and Step 2.
  final String? experimentId;

  /// Present only when a facts-only extraction was accepted without truncation.
  final FactsOnlyExtractionSnapshot? factsSnapshot;
  final SummarizeMapEvidenceDiagnosticFixtureId fixtureId;
  final SummarizeMapPromptVariant promptVariant;
  final String promptSha256;
  final int sourceChars;
  final String sourceSha256;
  final String inferenceStage;
  final int promptChars;
  final int rawResponseChars;
  final String stopReason;
  final bool truncated;
  final int normalInferenceCalls;
  final int correctiveInferenceCalls;
  final int inferenceMs;
  final bool firstPassSuccess;
  final Map<String, dynamic>? validatedEvidence;
  final WorkerError? failure;

  bool get completedWithValidEvidence =>
      validatedEvidence != null && failure == null;

  /// Accepted only after at least one corrective call (never counted as first-pass).
  bool get repairedSuccess =>
      completedWithValidEvidence && correctiveInferenceCalls > 0;
}
