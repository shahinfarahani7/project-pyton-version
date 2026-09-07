import 'artifact_install_coordinator.dart';
import 'model_runtime_manager.dart';

enum RuntimeUpgradeDecision {
  approved,
  rejected,
  rollbackRequired,
}

class RuntimeUpgradeEvaluationResult {
  RuntimeUpgradeEvaluationResult({
    required this.decision,
    required this.allowed,
    required this.rejectionReason,
    required this.dimensions,
  });

  final RuntimeUpgradeDecision decision;
  final bool allowed;
  final String? rejectionReason;
  final Map<String, String> dimensions;
}

/// Evaluates candidate runtime/model upgrades against pinned baseline (v2 §32.1, A24).
class RuntimeUpgradeCoordinator {
  RuntimeUpgradeCoordinator({
    ArtifactInstallCoordinator? installCoordinator,
  }) : _installCoordinator = installCoordinator ?? ArtifactInstallCoordinator.instance;

  final ArtifactInstallCoordinator _installCoordinator;

  RuntimeUpgradeEvaluationResult evaluateCandidate({
    required String candidateModelVersionId,
    required String baselineModelVersionId,
    required int candidateContextLimitTokens,
    required int baselineContextLimitTokens,
    required int openSessionCount,
    String? rollbackVersionId,
    String? benchmarkEvidencePath,
  }) {
    final dimensions = <String, String>{};

    if (_installCoordinator.installInProgress) {
      dimensions['lifecycle'] = 'fail:concurrent_install_blocked';
      return RuntimeUpgradeEvaluationResult(
        decision: RuntimeUpgradeDecision.rejected,
        allowed: false,
        rejectionReason: 'concurrent_install_blocked',
        dimensions: dimensions,
      );
    }

    if (openSessionCount > 0) {
      dimensions['lifecycle'] = 'fail:open_inference_sessions';
      return RuntimeUpgradeEvaluationResult(
        decision: RuntimeUpgradeDecision.rejected,
        allowed: false,
        rejectionReason: 'open_inference_sessions',
        dimensions: dimensions,
      );
    }

    if (candidateModelVersionId != baselineModelVersionId && rollbackVersionId == null) {
      dimensions['artifact_conversion'] = 'fail:rollback_version_required';
      return RuntimeUpgradeEvaluationResult(
        decision: RuntimeUpgradeDecision.rollbackRequired,
        allowed: false,
        rejectionReason: 'rollback_version_required',
        dimensions: dimensions,
      );
    }

    if (candidateContextLimitTokens > baselineContextLimitTokens) {
      dimensions['context'] = 'fail:context_limit_increased';
      return RuntimeUpgradeEvaluationResult(
        decision: RuntimeUpgradeDecision.rejected,
        allowed: false,
        rejectionReason: 'context_limit_increased_without_evaluation',
        dimensions: dimensions,
      );
    }

    if (benchmarkEvidencePath == null || benchmarkEvidencePath.isEmpty) {
      dimensions['quality'] = 'fail:benchmark_evidence_missing';
      return RuntimeUpgradeEvaluationResult(
        decision: RuntimeUpgradeDecision.rejected,
        allowed: false,
        rejectionReason: 'benchmark_evidence_missing',
        dimensions: dimensions,
      );
    }

    dimensions['artifact_conversion'] = 'pass';
    dimensions['lifecycle'] = 'pass';
    dimensions['context'] = 'pass';
    dimensions['quality'] = 'pass';
    dimensions['cancellation'] = 'pass';

    return RuntimeUpgradeEvaluationResult(
      decision: RuntimeUpgradeDecision.approved,
      allowed: true,
      rejectionReason: null,
      dimensions: dimensions,
    );
  }

  void assertUpgradeAllowed({
    required int openSessionCount,
    required String candidateModelVersionId,
    required String residentModelVersionId,
  }) {
    if (candidateModelVersionId == residentModelVersionId) {
      return;
    }
    _installCoordinator.assertUpgradeAllowedDuringSession(
      openSessionCount: openSessionCount,
    );
  }
}
