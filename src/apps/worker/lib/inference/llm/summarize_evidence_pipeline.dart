/// Feature gate for Phase 2 evidence transport (Map / intermediate Reduce).
abstract final class SummarizeEvidencePipeline {
  /// Enable via Android Studio / flutter run:
  /// `--dart-define=SUMMARIZE_EVIDENCE_V2=true`
  static const enabled = bool.fromEnvironment(
    'SUMMARIZE_EVIDENCE_V2',
    defaultValue: false,
  );

  static const schemaVersion = '2';

  static const promptVersionActive = '2.0';

  static const promptVersionLegacy = '1.0';

  /// Log once per summarize task when Phase 2 is active.
  static const activationLogMarker =
      '[PHASE2 EVIDENCE PIPELINE] active schemaVersion=2 promptVersion=2.0';

  static String get activePromptVersion =>
      enabled ? promptVersionActive : promptVersionLegacy;
}
