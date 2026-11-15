import 'device_capability_profile.dart';
import 'device_inference_policy_config.dart';
import 'device_snapshot.dart';
import 'long_form_execution_budget.dart';
import 'memory_sample.dart';
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
  DateTime? assignmentLeaseExpiresAt;

  /// Reads [GemmaModelRuntimeManager.residentIdentity]. Tests leave this null.
  ResidentEngineIdentity? Function()? readResidentEngine;

  /// Production reads Android MemoryInfo. Tests inject a sample.
  Future<MemorySample> Function()? readMemorySample;

  DateTime Function() clock = DateTime.now;

  /// A sample older than this is not used to allow generation.
  Duration memorySampleMaxAge = const Duration(seconds: 5);

  void debugReset() {
    config = const DeviceInferencePolicyConfig();
    cache = AdmissionResultCache();
    profile = null;
    textSelection = null;
    signals = const LongFormRuntimeSignals();
    assignmentLeaseExpiresAt = null;
    readResidentEngine = null;
    readMemorySample = null;
    clock = DateTime.now;
    memorySampleMaxAge = const Duration(seconds: 5);
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

  /// Reads a new memory sample and the current resident engine.
  ///
  /// A missing, failed, or stale sample returns an explicit rejection.
  /// It does not reuse the cached profile's RAM to allow generation.
  /// Benchmark data on the cached profile is copied onto the fresh profile.
  Future<ModelSelection?> reevaluate({
    required String taskType,
    required bool wantsVision,
  }) async {
    final base = profile;
    if (base == null) {
      return null;
    }
    final reader = readMemorySample;
    if (reader == null) {
      return _explicitRejection(const ['memory_snapshot_unknown']);
    }
    MemorySample sample;
    try {
      sample = await reader();
    } catch (_) {
      return _explicitRejection(const ['memory_snapshot_unknown']);
    }
    final age = clock().toUtc().difference(sample.sampledAt.toUtc());
    final usable = sample.freshness == MemorySampleFreshness.fresh &&
        sample.snapshot != null &&
        !age.isNegative &&
        age <= memorySampleMaxAge;
    if (!usable) {
      final unknown = sample.snapshot == null ||
          sample.freshness == MemorySampleFreshness.unavailable;
      return _explicitRejection(
        unknown ? const ['memory_snapshot_unknown'] : const ['memory_snapshot_stale'],
      );
    }
    final refreshed = DeviceCapabilityCollector.collect(
      sample.snapshot!,
      benchmark: base.benchmark,
    );
    if (refreshed.availableRamMb == null || refreshed.totalRamMb == null) {
      return _explicitRejection(const ['memory_snapshot_unknown']);
    }
    return _select(
      taskType: taskType,
      wantsVision: wantsVision,
      device: refreshed,
    );
  }

  ModelSelection _explicitRejection(List<String> codes) {
    final shape = textSelection ??
        _select(taskType: 'text.direct', wantsVision: false);
    return ModelSelection(
      selectedModelId: 'none',
      selectedBackend: 'none',
      selectedContextTokens: shape.selectedContextTokens,
      shortOutputTokens: shape.shortOutputTokens,
      mediumOutputTokens: shape.mediumOutputTokens,
      detailedOutputTokens: shape.detailedOutputTokens,
      perStageOutput: shape.perStageOutput,
      maxStages: shape.maxStages,
      hardMaxStages: shape.hardMaxStages,
      deviceTier: shape.deviceTier,
      hardwareTier: shape.hardwareTier,
      ramTier: shape.ramTier,
      cpuTier: shape.cpuTier,
      cpuClass: shape.cpuClass,
      memoryBudgetMb: null,
      maxImages: shape.maxImages,
      parallelInference: shape.parallelInference,
      residentModels: shape.residentModels,
      reason: codes.join(','),
      admitted: false,
      multimodalEligible: false,
      longFormBudget: shape.longFormBudget,
      riskLevel: AdmissionRisk.high,
      reasonCodes: codes,
    );
  }

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

  void noteAssignmentLease(DateTime leaseExpiresAt) {
    assignmentLeaseExpiresAt = leaseExpiresAt.toUtc();
  }

  LongFormRuntimeSignals readSignals() {
    final lease = assignmentLeaseExpiresAt;
    final remaining = lease?.difference(DateTime.now().toUtc()).inMilliseconds;
    return LongFormRuntimeSignals(
      elapsedMs: signals.elapsedMs,
      leaseRemainingMs: remaining ?? signals.leaseRemainingMs,
      batteryPercent: signals.batteryPercent,
      isCharging: signals.isCharging,
      thermalState: signals.thermalState,
    );
  }

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
      reasonCodes: current.reasonCodes,
    );
  }

  ModelSelection _select({
    required String taskType,
    required bool wantsVision,
    DeviceCapabilityProfile? device,
  }) {
    return ModelSelectionPolicy(
      config: config,
      admission: ModelAdmissionPolicy(config: config, cache: cache),
    ).select(
      device: device ?? profile!,
      request: ModelSelectionRequest(
        taskType: taskType,
        wantsVision: wantsVision,
      ),
      residentEngine: readResidentEngine?.call(),
    );
  }
}
