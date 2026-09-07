import 'dart:typed_data';

import 'package:edgemint_worker/runtime/gemma_inference_adapter.dart';
import 'package:edgemint_worker/runtime/gemma_model_runtime_manager.dart';
import 'package:edgemint_worker/runtime/inference_adapter.dart';
import 'package:edgemint_worker/runtime/model_runtime_manager.dart';
import 'package:edgemint_worker/runtime/runtime_exceptions.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:flutter_test/flutter_test.dart';

ModelArtifact _verifiedArtifact() {
  const signingKey = 'key';
  final bytes = Uint8List.fromList([1]);
  final digest = sha256Hex(bytes);
  return ModelArtifact(
    modelVersionId: 'mdv-qwen',
    digestSha256: digest,
    signatureSha256: sha256HexString('$digest:mdv-qwen:$signingKey'),
    backend: InferenceBackend.liteRt,
    bytes: bytes,
  );
}

void main() {
  group('InMemoryModelRuntimeManager', () {
    test('loads primary model once and reuses resident state', () async {
      final manager = InMemoryModelRuntimeManager(verifyArtifact: false);
      final artifact = _verifiedArtifact();
      await manager.ensureResident(artifact: artifact, signingKey: 'key');
      await manager.ensureResident(artifact: artifact, signingKey: 'key');
      expect(manager.loadCount, 1);
      expect(manager.residencyState, ModelResidencyState.resident);
      expect(manager.residentModelVersionId, 'mdv-qwen');
    });

    test('rejects unsigned artifacts when verification is enabled', () async {
      final manager = InMemoryModelRuntimeManager(verifyArtifact: true);
      const artifact = ModelArtifact(
        modelVersionId: 'mdv-qwen',
        digestSha256: 'digest',
        signatureSha256: '',
        backend: InferenceBackend.liteRt,
        bytes: [1],
      );

      await expectLater(
        manager.ensureResident(artifact: artifact, signingKey: 'key'),
        throwsA(isA<ModelIntegrityException>()),
      );
    });

    test('opens and closes a fresh session per inference stage', () async {      final manager = InMemoryModelRuntimeManager(verifyArtifact: false);
      const artifact = ModelArtifact(
        modelVersionId: 'mdv-qwen',
        digestSha256: 'digest',
        signatureSha256: 'sig',
        backend: InferenceBackend.liteRt,
        bytes: [1],
      );
      await manager.ensureResident(artifact: artifact, signingKey: 'key');

      final value = await manager.withFreshSession(
        stageId: 'inference',
        body: () async => 'ok',
      );

      expect(value, 'ok');
      expect(manager.sessionCount, 1);
      expect(manager.openSessionCount, 0);
      expect(manager.sessionStages, ['inference']);
    });

    test('rejects unload while a session is still open', () async {
      final manager = InMemoryModelRuntimeManager(verifyArtifact: false);
      const artifact = ModelArtifact(
        modelVersionId: 'mdv-qwen',
        digestSha256: 'digest',
        signatureSha256: 'sig',
        backend: InferenceBackend.liteRt,
        bytes: [1],
      );
      await manager.ensureResident(artifact: artifact, signingKey: 'key');

      await expectLater(
        manager.withFreshSession(
          stageId: 'inference',
          body: () async {
            expect(
              () => manager.unload(reason: ModelUnloadReason.memoryPressure),
              throwsStateError,
            );
            return null;
          },
        ),
        completes,
      );
    });

    test('unloads on lifecycle shutdown after sessions close', () async {
      final manager = InMemoryModelRuntimeManager(verifyArtifact: false);
      const artifact = ModelArtifact(
        modelVersionId: 'mdv-qwen',
        digestSha256: 'digest',
        signatureSha256: 'sig',
        backend: InferenceBackend.liteRt,
        bytes: [1],
      );
      await manager.ensureResident(artifact: artifact, signingKey: 'key');
      await manager.withFreshSession(stageId: 'inference', body: () async {});

      await manager.unload(reason: ModelUnloadReason.lifecycleShutdown);

      expect(manager.unloadCount, 1);
      expect(manager.residencyState, ModelResidencyState.unloaded);
      expect(manager.unloadReasons, [ModelUnloadReason.lifecycleShutdown]);
    });
  });

  group('GemmaLiteRtInferenceAdapter', () {
    test('exposes runtime manager with one-primary-model policy', () {
      final adapter = GemmaLiteRtInferenceAdapter();
      expect(adapter.runtimeManager, isA<GemmaModelRuntimeManager>());
      expect(adapter.runtimeManager.allowsOnlyOnePrimaryHeavyModel, isTrue);
      expect(adapter.runtimeManager.residencyState, ModelResidencyState.unloaded);
    });
  });
}
