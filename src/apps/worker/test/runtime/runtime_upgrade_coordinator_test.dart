import 'package:flutter_test/flutter_test.dart';

import 'package:edgemint_worker/runtime/runtime_exceptions.dart';
import 'package:edgemint_worker/runtime/runtime_upgrade_coordinator.dart';

void main() {
  group('RuntimeUpgradeCoordinator', () {
    final coordinator = RuntimeUpgradeCoordinator();

    test('approves candidate with rollback and benchmark evidence', () {
      final result = coordinator.evaluateCandidate(
        candidateModelVersionId: 'mdv_next',
        baselineModelVersionId: 'mdv_current',
        candidateContextLimitTokens: 1280,
        baselineContextLimitTokens: 1280,
        openSessionCount: 0,
        rollbackVersionId: 'mdv_current',
        benchmarkEvidencePath: 'evidence/benchmarks/qwen-v2.json',
      );
      expect(result.allowed, isTrue);
      expect(result.decision, RuntimeUpgradeDecision.approved);
    });

    test('requires rollback for model version change', () {
      final result = coordinator.evaluateCandidate(
        candidateModelVersionId: 'mdv_next',
        baselineModelVersionId: 'mdv_current',
        candidateContextLimitTokens: 1280,
        baselineContextLimitTokens: 1280,
        openSessionCount: 0,
      );
      expect(result.allowed, isFalse);
      expect(result.decision, RuntimeUpgradeDecision.rollbackRequired);
    });

    test('rejects upgrade while sessions are open', () {
      final result = coordinator.evaluateCandidate(
        candidateModelVersionId: 'mdv_next',
        baselineModelVersionId: 'mdv_current',
        candidateContextLimitTokens: 1280,
        baselineContextLimitTokens: 1280,
        openSessionCount: 1,
        rollbackVersionId: 'mdv_current',
        benchmarkEvidencePath: 'evidence/benchmarks/qwen-v2.json',
      );
      expect(result.allowed, isFalse);
      expect(result.rejectionReason, 'open_inference_sessions');
    });

    test('assertUpgradeAllowed throws when sessions open', () {
      expect(
        () => coordinator.assertUpgradeAllowed(
          openSessionCount: 1,
          candidateModelVersionId: 'mdv_next',
          residentModelVersionId: 'mdv_current',
        ),
        throwsA(isA<ModelIntegrityException>()),
      );
    });
  });
}
