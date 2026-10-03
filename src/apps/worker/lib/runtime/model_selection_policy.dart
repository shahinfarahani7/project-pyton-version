import 'device_capability_profile.dart';
import 'device_inference_policy_config.dart';
import 'device_snapshot.dart';
import 'long_form_execution_budget.dart';
import 'model_admission_policy.dart';
import 'worker_pipeline_log.dart';

enum GenerationQuality { standard, highest }

class ModelSelectionRequest {
  const ModelSelectionRequest({
    required this.taskType,
    this.wantsVision = false,
    this.quality = GenerationQuality.standard,
    this.candidates = InferenceModelCatalog.productionCandidates,
  });

  final String taskType;
  final bool wantsVision;
  final GenerationQuality quality;
  final List<ModelDescriptor> candidates;
}

class ModelSelection {
  const ModelSelection({
    required this.selectedModelId,
    required this.selectedBackend,
    required this.selectedContextTokens,
    required this.shortOutputTokens,
    required this.mediumOutputTokens,
    required this.detailedOutputTokens,
    required this.perStageOutput,
    required this.maxStages,
    required this.hardMaxStages,
    required this.deviceTier,
    required this.hardwareTier,
    required this.ramTier,
    required this.cpuTier,
    required this.cpuClass,
    required this.memoryBudgetMb,
    required this.maxImages,
    required this.parallelInference,
    required this.residentModels,
    required this.reason,
    required this.admitted,
    required this.multimodalEligible,
    required this.longFormBudget,
    required this.riskLevel,
  });

  final String selectedModelId;
  final String selectedBackend;
  final int selectedContextTokens;
  final int shortOutputTokens;
  final int mediumOutputTokens;
  final int detailedOutputTokens;
  final int perStageOutput;
  final int maxStages;
  final int hardMaxStages;
  final DeviceTier deviceTier;
  final HardwareTier hardwareTier;
  final RamTier ramTier;
  final HardwareTier cpuTier;
  final CpuClass cpuClass;
  final int? memoryBudgetMb;
  final int maxImages;
  final int parallelInference;
  final int residentModels;
  final String reason;
  final bool admitted;
  final bool multimodalEligible;
  final LongFormExecutionBudget longFormBudget;
  final AdmissionRisk riskLevel;

  int outputFor(String answerClass) {
    return switch (answerClass) {
      'long-form' => perStageOutput,
      'detailed' => detailedOutputTokens,
      'medium' => mediumOutputTokens,
      _ => shortOutputTokens,
    };
  }

  int selectedOutputLimit(String answerClass) => outputFor(answerClass);

  String configLog() =>
      '[DEVICE CONFIG] tier=${hardwareTier.name.toUpperCase()} '
      'model=$selectedModelId backend=$selectedBackend '
      'contextTokens=$selectedContextTokens context=$selectedContextTokens '
      'shortOutput=$shortOutputTokens short=$shortOutputTokens '
      'mediumOutput=$mediumOutputTokens medium=$mediumOutputTokens '
      'detailedOutput=$detailedOutputTokens detailed=$detailedOutputTokens '
      'longFormPerStage=$perStageOutput longStage=$perStageOutput '
      'maxStages=$maxStages hardMaxStages=$hardMaxStages '
      'vision=$maxImages memoryBudgetMb=${memoryBudgetMb ?? 'unknown'}';

  String logLine({required String taskType}) =>
      '[MODEL SELECT] taskType=$taskType selectedModel=$selectedModelId '
      'deviceTier=${hardwareTier.name.toUpperCase()} backend=$selectedBackend '
      'contextTokens=$selectedContextTokens perStageOutput=$perStageOutput '
      'hardMaxStages=$hardMaxStages';
}

abstract final class InferenceModelCatalog {
  static const gemma4E4bGpu = ModelDescriptor(
    modelId: 'mdv_gemma_4_e4b_it_gpu',
    modelName: 'Gemma 4 E4B',
    modelFileSizeBytes: 2969059328,
    modelFamily: 'gemma4',
    quantization: 'litert-lm-qat',
    supportsText: true,
    supportsVision: true,
    supportsAudio: true,
    recommendedContextTokens: 2048,
    minimumRamMb: 1500,
    recommendedRamMb: 3072,
    preferredBackend: 'GPU/OpenCL',
    artifactSha256:
        '4912bb5a9c30993c51a7711f763212077458529312175df0573a78323a2bb7ff',
    peakEstimatedMemoryMb: 1500,
    qualityRank: 1,
    peakEstimatedMemoryByContextMb: {1024: 900, 1536: 1100, 2048: 1500, 3072: 2200, 4096: 2800},
  );

  static const futureLarger = ModelDescriptor(
    modelId: 'future-larger-gemma',
    modelName: 'Future larger Gemma',
    modelFileSizeBytes: 8000000000,
    modelFamily: 'gemma4',
    quantization: 'unspecified',
    supportsText: true,
    supportsVision: true,
    supportsAudio: false,
    recommendedContextTokens: 4096,
    minimumRamMb: 6000,
    recommendedRamMb: 8000,
    preferredBackend: 'GPU',
    artifactSha256: 'future-larger-not-shipped',
    peakEstimatedMemoryMb: 5200,
    largerThanBaseline: true,
    qualityRank: 2,
    peakEstimatedMemoryByContextMb: {2048: 5200, 4096: 6400},
  );

  static const productionCandidates = [gemma4E4bGpu, futureLarger];
}

class ModelSelectionPolicy {
  const ModelSelectionPolicy({
    this.config = const DeviceInferencePolicyConfig(),
    this.admission = const ModelAdmissionPolicy(),
  });

  final DeviceInferencePolicyConfig config;
  final ModelAdmissionPolicy admission;

  ModelSelection select({
    required DeviceCapabilityProfile device,
    required ModelSelectionRequest request,
    RuntimeHealthSample? health,
    ResidentEngineIdentity? residentEngine,
  }) {
    final tierPolicy = _policyFor(device);
    final evaluations = <ModelAdmissionResult, ModelDescriptor>{};
    for (final model in request.candidates) {
      if (request.wantsVision && !model.supportsVision) {
        continue;
      }
      if (!model.supportsText && request.taskType.startsWith('text.')) {
        continue;
      }
      final preferred = _contextFor(device, model, tierPolicy);
      ModelAdmissionResult? fitted;
      for (final context in _contextsToTry(preferred)) {
        final result = admission.evaluate(
          device: device,
          model: model,
          contextTokens: context,
          visionRequested: request.wantsVision,
          residentEngine: residentEngine,
        );
        if (result.admitted) {
          fitted = result;
          break;
        }
        fitted ??= result;
      }
      if (fitted != null && fitted.admitted) {
        evaluations[fitted] = model;
      }
    }

    final admitted = evaluations.entries.where((entry) => entry.key.admitted).toList();
    admitted.sort((a, b) {
      if (request.quality == GenerationQuality.highest) {
        final quality = b.value.qualityRank.compareTo(a.value.qualityRank);
        if (quality != 0) {
          return quality;
        }
      } else if (a.value.modelId == InferenceModelCatalog.gemma4E4bGpu.modelId) {
        return -1;
      } else if (b.value.modelId == InferenceModelCatalog.gemma4E4bGpu.modelId) {
        return 1;
      }
      final risk = a.key.riskLevel.index.compareTo(b.key.riskLevel.index);
      if (risk != 0) {
        return risk;
      }
      final speedA = device.benchmark?.decodeChunksPerSecond ?? 0;
      final speedB = device.benchmark?.decodeChunksPerSecond ?? 0;
      return speedB.compareTo(speedA);
    });

    final chosen = admitted.isEmpty ? null : admitted.first;
    final model = chosen?.value ?? InferenceModelCatalog.gemma4E4bGpu;
    final admissionResult = chosen?.key;
    final admittedOk = admissionResult?.admitted ?? false;
    final fittedContext = admittedOk ? admissionResult!.selectedContextTokens : tierPolicy.contextTokens;
    final effective = _downgradedPolicy(tierPolicy, fittedContext);
    var perStage = effective.perStageOutput;
    var hard = effective.hardMaxStages;
    var maxStages = effective.maxStages;
    final promoted = (device.hardwareTier == HardwareTier.t4 ||
            device.hardwareTier == HardwareTier.t5) &&
        admissionResult?.riskLevel == AdmissionRisk.low &&
        (device.benchmark?.sustainedDecodeChunksPerSecond ?? 0) >=
            config.thresholds.highDecodeChunksPerSecond &&
        (device.thermalState == ThermalState.normal ||
            device.thermalState == ThermalState.warm);
    if (promoted && perStage < config.tiers.promotedPerStageOutput) {
      perStage = config.tiers.promotedPerStageOutput;
    }
    var context = fittedContext;
    if (admittedOk) {
      context = admissionResult!.selectedContextTokens;
    }
    if ((device.totalRamMb == null || device.availableRamMb == null) &&
        context > config.baselineContextTokens) {
      context = config.baselineContextTokens;
    }
    var budget = LongFormExecutionBudget(
      maxStages: maxStages,
      hardMaxStages: hard,
      maxElapsedMs: effective.maxElapsedMs,
      minimumLeaseRemainingMs: effective.minimumLeaseRemainingMs,
      minimumBatteryPercent: effective.minimumBatteryPercent,
      maximumThermalState: effective.maximumThermalState,
      multimodalEligible: admittedOk &&
          (admissionResult?.visionEligible ?? false) &&
          !effective.multimodalRestricted,
    );
    if (health != null) {
      budget = budget.degrade(health, config: config, tierTable: config.tiers);
      hard = budget.hardMaxStages;
      maxStages = budget.maxStages;
    }
    final downgraded = admittedOk && fittedContext < tierPolicy.contextTokens;
    final reason = admittedOk
        ? (downgraded
            ? 'context_downgraded_to_$fittedContext'
            : (admissionResult!.reasons.isEmpty ? 'admitted' : admissionResult.reasons.join(',')))
        : 'no_admitted_model';
    final selection = ModelSelection(
      selectedModelId: admittedOk ? model.modelId : 'none',
      selectedBackend: admittedOk ? admissionResult!.selectedBackend : 'none',
      selectedContextTokens: context,
      shortOutputTokens: effective.shortOutput,
      mediumOutputTokens: effective.mediumOutput,
      detailedOutputTokens: effective.detailedOutput,
      perStageOutput: perStage,
      maxStages: maxStages,
      hardMaxStages: hard,
      deviceTier: device.tier,
      hardwareTier: device.hardwareTier,
      ramTier: device.ramTier,
      cpuTier: device.cpuTier,
      cpuClass: device.cpuClass,
      memoryBudgetMb: config.memory.safeBudgetMb(
        availableRamMb: device.availableRamMb,
        totalRamMb: device.totalRamMb,
      ),
      maxImages: effective.maxImages,
      parallelInference: effective.parallelInference,
      residentModels: effective.residentModels,
      reason: reason,
      admitted: admittedOk,
      multimodalEligible: budget.multimodalEligible,
      longFormBudget: budget,
      riskLevel: admissionResult?.riskLevel ?? AdmissionRisk.high,
    );
    WorkerPipelineLog.info(
      WorkerPipelineLog.model,
      selection.logLine(taskType: request.taskType),
    );
    return selection;
  }

  List<int> _contextsToTry(int preferred) {
    const ladder = [4096, 3072, 2048, 1536, 1024];
    final contexts = <int>[];
    if (preferred > 0) {
      contexts.add(preferred);
    }
    for (final context in ladder) {
      if (context < preferred && !contexts.contains(context)) {
        contexts.add(context);
      }
    }
    return contexts;
  }

  /// Lower output and stage limits when memory only fits a smaller context.
  TierExecutionPolicy _downgradedPolicy(TierExecutionPolicy current, int context) {
    if (context >= current.contextTokens) {
      return current;
    }
    final table = config.tiers;
    TierExecutionPolicy? best;
    for (final policy in [table.t0, table.t1, table.t2, table.t3, table.t4, table.t5]) {
      if (policy.contextTokens <= context &&
          (best == null || policy.contextTokens > best.contextTokens)) {
        best = policy;
      }
    }
    return best ?? table.t0;
  }

  TierExecutionPolicy _policyFor(DeviceCapabilityProfile device) {
    if (device.tier == DeviceTier.unsupported) {
      return config.tiers.t0;
    }
    return config.tiers.forHardware(device.hardwareTier);
  }

  int _contextFor(
    DeviceCapabilityProfile device,
    ModelDescriptor model,
    TierExecutionPolicy tierPolicy,
  ) {
    if (model.largerThanBaseline) {
      return model.recommendedContextTokens;
    }
    final benchmark = device.benchmark;
    final extra = tierPolicy.benchmarkedContextTokens;
    if (extra != null &&
        benchmark != null &&
        benchmark.modelSha256 == model.artifactSha256 &&
        benchmark.succeededForContext(extra)) {
      return extra;
    }
    final requested = tierPolicy.contextTokens;
    if ((device.totalRamMb == null || device.availableRamMb == null) &&
        requested > config.baselineContextTokens) {
      return config.baselineContextTokens;
    }
    return requested;
  }
}
