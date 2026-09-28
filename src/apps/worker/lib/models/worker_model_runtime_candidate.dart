import 'dart:io';

import '../runtime/device_snapshot.dart';
import 'worker_model_artifact_descriptor.dart';
import 'worker_model_catalog.dart';

/// Runtime artifact identities for Gemma 4 E4B LiteRT-LM benchmarks.
enum WorkerModelRuntimeCandidateId {
  /// General `gemma-4-E4B-it.litertlm` (production default).
  generalLitertLmA,

  /// GPU-targeted `gemma-4-E4B-it-gpu.litertlm` (benchmark-only until selected).
  gpuLitertLmG,
}

/// Result of eligibility / selection checks (does not perform native load).
class WorkerModelRuntimeCandidateSelection {
  const WorkerModelRuntimeCandidateSelection({
    required this.candidateId,
    required this.descriptor,
    required this.eligible,
    this.reason,
  });

  final WorkerModelRuntimeCandidateId candidateId;
  final WorkerModelArtifactDescriptor descriptor;
  final bool eligible;
  final String? reason;
}

abstract final class WorkerModelRuntimeCandidateRegistry {
  static const productionCandidateId =
      WorkerModelRuntimeCandidateId.generalLitertLmA;

  static const allRuntimeCandidates = <WorkerModelRuntimeCandidateId>[
    WorkerModelRuntimeCandidateId.generalLitertLmA,
    WorkerModelRuntimeCandidateId.gpuLitertLmG,
  ];

  static WorkerModelArtifactDescriptor descriptorFor(
    WorkerModelRuntimeCandidateId id,
  ) {
    switch (id) {
      case WorkerModelRuntimeCandidateId.generalLitertLmA:
        return WorkerModelCatalog.generalRuntimeDescriptor;
      case WorkerModelRuntimeCandidateId.gpuLitertLmG:
        return WorkerModelCatalog.gpuRuntimeDescriptor;
    }
  }

  static String modelVersionIdFor(WorkerModelRuntimeCandidateId id) {
    switch (id) {
      case WorkerModelRuntimeCandidateId.generalLitertLmA:
        return WorkerModelCatalog.modelVersionId;
      case WorkerModelRuntimeCandidateId.gpuLitertLmG:
        return WorkerModelCatalog.gpuModelVersionId;
    }
  }

  static WorkerModelRuntimeCandidateId? benchmarkOverrideFromEnvironment() {
    const value = String.fromEnvironment('WORKER_BENCHMARK_RUNTIME_CANDIDATE');
    switch (value.toLowerCase()) {
      case 'a':
      case 'general':
        return WorkerModelRuntimeCandidateId.generalLitertLmA;
      case 'g':
      case 'gpu':
        return WorkerModelRuntimeCandidateId.gpuLitertLmG;
      default:
        return null;
    }
  }

  static bool isKnownRuntimeModelVersionId(String modelVersionId) {
    return modelVersionId == WorkerModelCatalog.modelVersionId ||
        modelVersionId == WorkerModelCatalog.gpuModelVersionId;
  }
}

abstract final class WorkerModelRuntimeCandidateSelector {
  /// Production remains Candidate A until a measured benchmark selects otherwise.
  static WorkerModelRuntimeCandidateId get productionActiveCandidateId =>
      WorkerModelRuntimeCandidateRegistry.productionCandidateId;

  static WorkerModelRuntimeCandidateSelection evaluate({
    required WorkerModelRuntimeCandidateId candidateId,
    required DeviceSnapshot device,
    required bool benchmarkMode,
  }) {
    final descriptor =
        WorkerModelRuntimeCandidateRegistry.descriptorFor(candidateId);

    if (!descriptor.isRuntimeReady) {
      return WorkerModelRuntimeCandidateSelection(
        candidateId: candidateId,
        descriptor: descriptor,
        eligible: false,
        reason: 'Descriptor is not runtime-ready',
      );
    }

    if (candidateId == WorkerModelRuntimeCandidateId.gpuLitertLmG) {
      if (device.isX86Android) {
        return WorkerModelRuntimeCandidateSelection(
          candidateId: candidateId,
          descriptor: descriptor,
          eligible: false,
          reason: 'GPU artifact is not eligible on x86 Android emulator',
        );
      }
      if (!Platform.isAndroid) {
        if (!benchmarkMode) {
          return WorkerModelRuntimeCandidateSelection(
            candidateId: candidateId,
            descriptor: descriptor,
            eligible: false,
            reason: 'GPU artifact requires Android ARM device',
          );
        }
        // Host-side unit tests: snapshot-only eligibility; live benchmark still requires device.
      } else if (!device.available) {
        return WorkerModelRuntimeCandidateSelection(
          candidateId: candidateId,
          descriptor: descriptor,
          eligible: false,
          reason: 'Device snapshot unavailable',
        );
      }
    }

    if (!benchmarkMode &&
        candidateId != WorkerModelRuntimeCandidateRegistry.productionCandidateId) {
      return WorkerModelRuntimeCandidateSelection(
        candidateId: candidateId,
        descriptor: descriptor,
        eligible: false,
        reason: 'Non-production candidate requires benchmark mode',
      );
    }

    return WorkerModelRuntimeCandidateSelection(
      candidateId: candidateId,
      descriptor: descriptor,
      eligible: true,
    );
  }
}
