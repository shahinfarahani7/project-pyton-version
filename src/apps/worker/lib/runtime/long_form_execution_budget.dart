import 'device_inference_policy_config.dart';
import 'device_snapshot.dart';
import 'worker_pipeline_log.dart';

class LongFormRuntimeSignals {
  const LongFormRuntimeSignals({
    this.elapsedMs = 0,
    this.leaseRemainingMs,
    this.batteryPercent,
    this.isCharging,
    this.thermalState,
  });

  final int elapsedMs;
  final int? leaseRemainingMs;
  final int? batteryPercent;
  final bool? isCharging;
  final ThermalState? thermalState;

  static String display(Object? value) => value == null ? 'unknown' : '$value';
}

class RuntimeHealthSample {
  const RuntimeHealthSample({
    this.decodeChunksPerSecond,
    this.baselineDecodeChunksPerSecond,
    this.thermalState,
    this.availableRamMb,
    this.rejectHeavierModels = false,
  });

  final double? decodeChunksPerSecond;
  final double? baselineDecodeChunksPerSecond;
  final ThermalState? thermalState;
  final int? availableRamMb;
  final bool rejectHeavierModels;
}

class LongFormBudgetDecision {
  const LongFormBudgetDecision({
    required this.shouldContinue,
    required this.reason,
    required this.stageIndex,
    required this.signals,
  });

  final bool shouldContinue;
  final String reason;
  final int stageIndex;
  final LongFormRuntimeSignals signals;

  String logLine() =>
      '[RUNTIME BUDGET] stageIndex=$stageIndex '
      'elapsedMs=${signals.elapsedMs} '
      'leaseRemainingMs=${LongFormRuntimeSignals.display(signals.leaseRemainingMs)} '
      'battery=${LongFormRuntimeSignals.display(signals.batteryPercent)} '
      'thermal=${signals.thermalState?.name ?? 'unknown'} '
      'shouldContinue=$shouldContinue reason=$reason';
}

/// Stage continuation limits that are independent of text completion.
class LongFormExecutionBudget {
  const LongFormExecutionBudget({
    required this.maxStages,
    required this.hardMaxStages,
    required this.maxElapsedMs,
    required this.minimumLeaseRemainingMs,
    required this.minimumBatteryPercent,
    required this.maximumThermalState,
    this.multimodalEligible = false,
    this.rejectHeavierModels = false,
    this.initialSignals = const LongFormRuntimeSignals(),
  });

  final int maxStages;
  final int hardMaxStages;
  final int maxElapsedMs;
  final int minimumLeaseRemainingMs;
  final int minimumBatteryPercent;
  final ThermalState maximumThermalState;
  final bool multimodalEligible;
  final bool rejectHeavierModels;
  final LongFormRuntimeSignals initialSignals;

  /// Wall-clock estimate for one more stage, taken from this budget's own
  /// elapsed ceiling and hard stage count.
  int get estimatedNextStageMs {
    final stages = hardMaxStages < 1 ? 1 : hardMaxStages;
    return maxElapsedMs ~/ stages;
  }

  /// Lease margin already stored on the tier policy.
  int get submissionSafetyMarginMs => minimumLeaseRemainingMs;

  bool leaseMarginFits(int? leaseRemainingMs) {
    if (leaseRemainingMs == null) {
      return true;
    }
    return estimatedNextStageMs + submissionSafetyMarginMs < leaseRemainingMs;
  }

  int thermalRank(ThermalState state) => switch (state) {
        ThermalState.normal => 0,
        ThermalState.warm => 1,
        ThermalState.throttled => 2,
        ThermalState.critical => 3,
      };

  LongFormBudgetDecision evaluate({
    required int stageIndex,
    required int stageCount,
    LongFormRuntimeSignals? signals,
  }) {
    final current = signals ?? initialSignals;
    final decision = _decide(stageCount, current);
    final logged = LongFormBudgetDecision(
      shouldContinue: decision.$1,
      reason: decision.$2,
      stageIndex: stageIndex,
      signals: current,
    );
    WorkerPipelineLog.info(WorkerPipelineLog.exec, logged.logLine());
    return logged;
  }

  (bool, String) _decide(int stageCount, LongFormRuntimeSignals signals) {
    if (stageCount >= hardMaxStages) {
      return (false, 'hard_stage_limit');
    }
    if (signals.elapsedMs >= maxElapsedMs) {
      return (false, 'elapsed');
    }
    final lease = signals.leaseRemainingMs;
    if (!leaseMarginFits(lease)) {
      return (false, 'lease_budget_exhausted');
    }
    final thermal = signals.thermalState;
    if (thermal != null && thermalRank(thermal) > thermalRank(maximumThermalState)) {
      return (false, 'thermal');
    }
    final battery = signals.batteryPercent;
    final charging = signals.isCharging == true;
    if (battery != null && !charging && battery < minimumBatteryPercent) {
      return (false, 'battery');
    }
    return (true, 'ok');
  }

  LongFormExecutionBudget degrade(
    RuntimeHealthSample sample, {
    DeviceInferencePolicyConfig config = const DeviceInferencePolicyConfig(),
    TierPolicyTable tierTable = const TierPolicyTable(),
  }) {
    var hard = hardMaxStages;
    var stages = maxStages;
    var multimodal = multimodalEligible;
    var rejectHeavier = rejectHeavierModels;
    final baseline = sample.baselineDecodeChunksPerSecond;
    final decode = sample.decodeChunksPerSecond;
    if (baseline != null &&
        baseline > 0 &&
        decode != null &&
        decode < baseline * config.decodeDropRatio) {
      hard = hard > tierTable.low.hardMaxStages ? tierTable.low.hardMaxStages : hard;
      stages = stages > tierTable.low.maxStages ? tierTable.low.maxStages : stages;
    }
    final thermal = sample.thermalState;
    if (thermal == ThermalState.throttled || thermal == ThermalState.critical) {
      hard = hard > tierTable.low.hardMaxStages ? tierTable.low.hardMaxStages : hard;
      multimodal = false;
    }
    final available = sample.availableRamMb;
    if (available != null && available < config.thresholds.lowAvailableRamMb) {
      hard = tierTable.low.hardMaxStages;
      stages = tierTable.low.maxStages;
      multimodal = false;
      rejectHeavier = true;
    }
    if (hard < stages) {
      stages = hard;
    }
    return LongFormExecutionBudget(
      maxStages: stages,
      hardMaxStages: hard,
      maxElapsedMs: maxElapsedMs,
      minimumLeaseRemainingMs: minimumLeaseRemainingMs,
      minimumBatteryPercent: minimumBatteryPercent,
      maximumThermalState: maximumThermalState,
      multimodalEligible: multimodal,
      rejectHeavierModels: rejectHeavier,
      initialSignals: initialSignals,
    );
  }
}
