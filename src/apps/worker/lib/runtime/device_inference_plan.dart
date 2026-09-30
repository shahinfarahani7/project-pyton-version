import 'device_capability_profile.dart';
import 'device_inference_policy_config.dart';
import 'device_snapshot.dart';
import 'long_form_execution_budget.dart';
import 'model_admission_policy.dart';
import 'model_selection_policy.dart';
import 'worker_pipeline_log.dart';

/// Latest device profile and the generation policy derived from it.
class DeviceInferencePlan {
  DeviceInferencePlan._();

  static final DeviceInferencePlan instance = DeviceInferencePlan._();

  DeviceInferencePolicyConfig config = const DeviceInferencePolicyConfig();
  AdmissionResultCache cache = AdmissionResultCache();
  DeviceCapabilityProfile? profile;
  ModelSelection? textSelection;
  LongFormRuntimeSignals signals = const LongFormRuntimeSignals();

  void debugReset() {
    config = const DeviceInferencePolicyConfig();
    cache = AdmissionResultCache();
    profile = null;
    textSelection = null;
    signals = const LongFormRuntimeSignals();
  }

  void useStore(AdmissionCacheStore store) {
    cache = AdmissionResultCache(store: store);
  }

  void publish(DeviceCapabilityProfile next) {
    profile = next;
    WorkerPipelineLog.info(WorkerPipelineLog.boot, next.hardwareLog());
    WorkerPipelineLog.info(WorkerPipelineLog.boot, next.tierLog());
    WorkerPipelineLog.info(WorkerPipelineLog.boot, next.lookupLog());
    WorkerPipelineLog.info(WorkerPipelineLog.boot, next.profileLog());
    textSelection = _select(taskType: 'text.direct', wantsVision: false);
    final selection = textSelection;
    if (selection != null) {
      WorkerPipelineLog.info(WorkerPipelineLog.boot, selection.configLog());
    }
  }

  void publishFromSnapshot(DeviceSnapshot snapshot) {
    publish(
      DeviceCapabilityCollector.collect(
        snapshot,
        benchmark: profile?.benchmark,
      ),
    );
    signals = LongFormRuntimeSignals(
      leaseRemainingMs: signals.leaseRemainingMs,
      elapsedMs: signals.elapsedMs,
      batteryPercent: snapshot.batteryPercent,
      isCharging: snapshot.isCharging,
      thermalState: snapshot.thermalState,
    );
  }

  /// Context chosen for the next resident load. Null when no profile exists,
  /// so existing benchmark/catalog behavior stays in tests that never publish.
  int? contextTokensForResidentLoad() => textSelection?.selectedContextTokens;

  ModelSelection? selectionFor({
    required String taskType,
    required bool wantsVision,
  }) {
    final current = profile;
    if (current == null) {
      return null;
    }
    if (!wantsVision && textSelection != null) {
      return textSelection;
    }
    return _select(taskType: taskType, wantsVision: wantsVision);
  }

  LongFormRuntimeSignals readSignals() => signals;

  void noteHealth(RuntimeHealthSample sample) {
    final current = textSelection;
    if (current == null || profile == null) {
      return;
    }
    final budget = current.longFormBudget.degrade(sample, config: config);
    textSelection = ModelSelection(
      selectedModelId: current.selectedModelId,
      selectedBackend: current.selectedBackend,
      selectedContextTokens: current.selectedContextTokens,
      shortOutputTokens: current.shortOutputTokens,
      mediumOutputTokens: current.mediumOutputTokens,
      detailedOutputTokens: current.detailedOutputTokens,
      perStageOutput: current.perStageOutput,
      maxStages: budget.maxStages,
      hardMaxStages: budget.hardMaxStages,
      deviceTier: current.deviceTier,
      hardwareTier: current.hardwareTier,
      ramTier: current.ramTier,
      cpuTier: current.cpuTier,
      cpuClass: current.cpuClass,
      memoryBudgetMb: current.memoryBudgetMb,
      maxImages: current.maxImages,
      parallelInference: current.parallelInference,
      residentModels: current.residentModels,
      reason: current.reason,
      admitted: current.admitted,
      multimodalEligible: budget.multimodalEligible,
      longFormBudget: budget,
      riskLevel: current.riskLevel,
    );
  }

  ModelSelection _select({
    required String taskType,
    required bool wantsVision,
  }) {
    return ModelSelectionPolicy(
      config: config,
      admission: ModelAdmissionPolicy(config: config, cache: cache),
    ).select(
      device: profile!,
      request: ModelSelectionRequest(
        taskType: taskType,
        wantsVision: wantsVision,
      ),
    );
  }
}
