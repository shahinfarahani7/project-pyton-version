import 'package:edgemint_worker/runtime/artifact_install_coordinator.dart';
import 'package:edgemint_worker/runtime/inference_adapter.dart';
import 'package:edgemint_worker/runtime/model_runtime_manager.dart';
import 'package:edgemint_worker/runtime/runtime_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArtifactInstallCoordinator', () {
    setUp(() {
      ArtifactInstallCoordinator.instance.resetForTest();
    });

    test('serializes concurrent install operations', () async {
      final coordinator = ArtifactInstallCoordinator.instance;
      final first = coordinator.runExclusiveInstall<void>(
        modelVersionId: 'mdv_a',
        operation: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        },
      );

      expect(
        () => coordinator.assertNoConcurrentInstall(),
        throwsA(isA<ModelIntegrityException>()),
      );

      await first;
      expect(coordinator.generation, 1);
      expect(coordinator.activeModelVersionId, 'mdv_a');
    });

    test('blocks upgrade while inference sessions are open', () {
      final coordinator = ArtifactInstallCoordinator.instance;
      expect(
        () => coordinator.assertUpgradeAllowedDuringSession(openSessionCount: 1),
        throwsA(isA<ModelIntegrityException>()),
      );
    });
  });

  group('InMemoryModelRuntimeManager upgrade guard', () {
    test('rejects model replacement while session is open', () async {
      final manager = InMemoryModelRuntimeManager(verifyArtifact: false);
      const first = ModelArtifact(
        modelVersionId: 'mdv-a',
        digestSha256: 'digest-a',
        signatureSha256: 'sig-a',
        backend: InferenceBackend.liteRt,
        bytes: [1],
      );
      const second = ModelArtifact(
        modelVersionId: 'mdv-b',
        digestSha256: 'digest-b',
        signatureSha256: 'sig-b',
        backend: InferenceBackend.liteRt,
        bytes: [2],
      );
      await manager.ensureResident(artifact: first, signingKey: 'key');

      await expectLater(
        manager.withFreshSession(
          stageId: 'inference',
          body: () async {
            await expectLater(
              manager.ensureResident(artifact: second, signingKey: 'key'),
              throwsA(isA<ModelIntegrityException>()),
            );
          },
        ),
        completes,
      );
    });
  });
}
