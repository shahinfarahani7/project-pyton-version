import '../../contracts/worker_error.dart';
import 'summarize_chunk_experiment.dart';
import 'summarize_evidence_pipeline.dart';

/// Multi-chunk summarize evidence contract, resolved once per task.
enum SummarizePipelineMode {
  /// Evidence v2 off: legacy five-field Map partials.
  legacy,

  /// Evidence v2 with classified openItems/priority at Map.
  evidenceV2,

  /// Evidence v2 shape with every statement in facts; openItems/priority empty
  /// until the final Reduce.
  factsOnly,
}

extension SummarizePipelineModeLabels on SummarizePipelineMode {
  String get logLabel => switch (this) {
        SummarizePipelineMode.legacy => 'legacy',
        SummarizePipelineMode.evidenceV2 => 'evidenceV2',
        SummarizePipelineMode.factsOnly => 'factsOnly',
      };

  bool get isFactsOnly => this == SummarizePipelineMode.factsOnly;

  String get multiChunkRouteLabel => switch (this) {
        SummarizePipelineMode.legacy => 'legacyMapReduce',
        SummarizePipelineMode.evidenceV2 => 'existingEvidenceMapReduce',
        SummarizePipelineMode.factsOnly => 'factsOnlyMapReduce',
      };
}

abstract final class SummarizeFactsOnlyPipeline {
  static const configurationName = 'SUMMARIZE_FACTS_ONLY_PIPELINE';

  static const requested = bool.fromEnvironment(
    configurationName,
    defaultValue: false,
  );

  static const checkpointSuffix = '+factsOnly';
}

/// Mode for callers that never opt into facts-only (e.g. document.summarize).
SummarizePipelineMode get defaultSummarizePipelineMode =>
    SummarizeEvidencePipeline.enabled
        ? SummarizePipelineMode.evidenceV2
        : SummarizePipelineMode.legacy;

/// text.summarize only; throws before inference on an invalid flag combination.
SummarizePipelineMode resolveTextSummarizePipelineMode() {
  if (!SummarizeFactsOnlyPipeline.requested) {
    return defaultSummarizePipelineMode;
  }
  final mode = SummarizePipelineMode.factsOnly;
  assertSummarizePipelineModeValid(mode);
  return mode;
}

void assertSummarizePipelineModeValid(SummarizePipelineMode mode) {
  if (mode.isFactsOnly && !SummarizeEvidencePipeline.enabled) {
    throw const WorkerError(
      code: WorkerErrorCode.invalidTask,
      message:
          '${SummarizeFactsOnlyPipeline.configurationName}=true requires '
          'SUMMARIZE_EVIDENCE_V2=true',
      retryable: false,
      stage: WorkerTaskStage.validation,
    );
  }
}

/// Checkpoint prompt identity; facts-only never resumes classified-evidence
/// checkpoints, and the optional source-chunk cap suffix still composes.
String summarizeCheckpointPromptVersion({required bool factsOnly}) {
  final base = SummarizeEvidencePipeline.activePromptVersion;
  return SummarizeChunkExperiment.activeCheckpointPromptVersion(
    factsOnly ? '$base${SummarizeFactsOnlyPipeline.checkpointSuffix}' : base,
  );
}
