import 'dart:typed_data';

import 'package:edgemint_worker/models/worker_model_artifact_descriptor.dart';
import 'package:edgemint_worker/models/worker_model_catalog.dart';
import 'package:edgemint_worker/models/worker_model_runtime_candidate.dart';
import 'package:edgemint_worker/runtime/device_snapshot.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/runtime/gemma4_e4b_gpu_benchmark.dart';
import 'package:edgemint_worker/runtime/inference_adapter.dart';
import 'package:edgemint_worker/runtime/model_runtime_manager.dart';
import 'package:edgemint_worker/runtime/worker_model_format_gate.dart';
import 'package:edgemint_worker/runtime/worker_model_installer.dart';
import 'package:flutter_test/flutter_test.dart';

DeviceSnapshot _armDevice() {
  return const DeviceSnapshot(
    available: true,
    batteryPercent: 80,
    isCharging: false,
    thermalState: ThermalState.normal,
    network: NetworkKind.wifi,
    freeStorageMb: 8000,
    withinSchedule: true,
    consentsGranted: ['inference'],
    isEmulator: false,
    isX86Android: false,
    deviceTotalRamMb: 8192,
    deviceAvailableRamMb: 4096,
  );
}

void main() {
  group('WorkerModelRuntimeCandidateRegistry', () {
    test('Candidate A and G are Gemma4 LITERT_LM runtime descriptors', () {
      for (final id in WorkerModelRuntimeCandidateRegistry.allRuntimeCandidates) {
        final d = WorkerModelRuntimeCandidateRegistry.descriptorFor(id);
        expect(d.modelFamily, 'gemma4');
        expect(d.runtimeFormat, WorkerModelRuntimeFormat.litertLm);
        expect(d.isRuntimeReady, isTrue);
        expect(
          WorkerModelFormatGate.validateForRuntime(
            expected: d,
            filePath: '/data/app/${d.artifactFileName}',
            fileSizeBytes: WorkerModelFormatGate.minLitertLmBytes + 1,
          ).accepted,
          isTrue,
        );
      }
    });

    test('production default remains Candidate A', () {
      expect(
        WorkerModelRuntimeCandidateSelector.productionActiveCandidateId,
        WorkerModelRuntimeCandidateId.generalLitertLmA,
      );
      expect(
        WorkerModelCatalog.activeRuntimeDescriptor,
        WorkerModelCatalog.generalRuntimeDescriptor,
      );
    });

    test('known upstream GPU digest matches Hugging Face LFS metadata', () {
      expect(
        WorkerModelCatalog.gpuRuntimeDescriptor.artifactSha256,
        WorkerModelCatalog.knownGpuArtifactSha256,
      );
    });
  });

  group('WorkerModelRuntimeCandidateSelector', () {
    test('GPU candidate eligible on ARM Android in benchmark mode', () {
      final selection = WorkerModelRuntimeCandidateSelector.evaluate(
        candidateId: WorkerModelRuntimeCandidateId.gpuLitertLmG,
        device: _armDevice(),
        benchmarkMode: true,
      );
      expect(selection.eligible, isTrue);
      expect(selection.descriptor.targetBackend, WorkerModelTargetBackend.gpu);
    });

    test('GPU candidate not eligible on x86 emulator', () {
      final selection = WorkerModelRuntimeCandidateSelector.evaluate(
        candidateId: WorkerModelRuntimeCandidateId.gpuLitertLmG,
        device: _armDevice().copyWith(isX86Android: true),
        benchmarkMode: true,
      );
      expect(selection.eligible, isFalse);
      expect(selection.reason, contains('x86'));
    });

    test('GPU candidate blocked outside benchmark mode', () {
      final selection = WorkerModelRuntimeCandidateSelector.evaluate(
        candidateId: WorkerModelRuntimeCandidateId.gpuLitertLmG,
        device: _armDevice(),
        benchmarkMode: false,
      );
      expect(selection.eligible, isFalse);
    });
  });

  group('benchmark lifecycle counters', () {
    test('three sequential tasks reuse resident model and isolate sessions', () async {
      final manager = InMemoryModelRuntimeManager(verifyArtifact: false);
      final bytes = Uint8List.fromList([1]);
      final digest = sha256Hex(bytes);
      final artifact = ModelArtifact(
        modelVersionId: WorkerModelCatalog.modelVersionId,
        digestSha256: digest,
        signatureSha256: sha256HexString('$digest:${WorkerModelCatalog.modelVersionId}:k'),
        backend: InferenceBackend.liteRt,
        bytes: bytes,
      );

      await manager.ensureResident(artifact: artifact, signingKey: 'k');
      for (var i = 0; i < 3; i++) {
        await manager.withFreshSession(
          stageId: 'bench-$i',
          body: () async {},
        );
      }
      expect(manager.loadCount, 1);
      expect(manager.sessionCount, 3);
      expect(manager.openSessionCount, 0);
    });

    test('benchmark activation failure leaves missing file false without throw', () async {
      final ok = await WorkerModelInstaller.activateBenchmarkArtifactFile(
        '/no/such/gemma-4-E4B-it-gpu.litertlm',
      );
      expect(ok, isFalse);
    });
  });
}
