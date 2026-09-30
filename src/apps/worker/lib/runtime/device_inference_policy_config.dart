import 'device_snapshot.dart';

enum HardwareTier { t0, t1, t2, t3, t4, t5 }

enum RamTier { t0, t1, t2, t3, t4, t5 }

enum CpuClass { c0, c1, c2, c3, c4, unknown }

/// All tunable admission, tier, and long-form numbers live here.
class DeviceInferencePolicyConfig {
  const DeviceInferencePolicyConfig({
    this.thresholds = const DeviceTierThresholds(),
    this.memory = const MemorySafetyConfig(),
    this.tiers = const TierPolicyTable(),
    this.runtimeVersion = 'litert-lm-gemma4',
    this.appVersion = const String.fromEnvironment(
      'WORKER_APP_VERSION',
      defaultValue: 'dev',
    ),
    this.oomRamImprovementMb = 512,
    this.visionHeadroomMb = 512,
    this.decodeDropRatio = 0.6,
    this.baselineContextTokens = 2048,
    this.wideContextTokens = 4096,
  });

  final DeviceTierThresholds thresholds;
  final MemorySafetyConfig memory;
  final TierPolicyTable tiers;
  final String runtimeVersion;
  final String appVersion;
  final int oomRamImprovementMb;
  final int visionHeadroomMb;
  final double decodeDropRatio;
  final int baselineContextTokens;
  final int wideContextTokens;
}

class DeviceTierThresholds {
  const DeviceTierThresholds({
    this.lowAvailableRamMb = 2200,
    this.highAvailableRamMb = 4500,
    this.lowDecodeChunksPerSecond = 1.8,
    this.highDecodeChunksPerSecond = 3.5,
    this.weakThermalHeadroom = 0.2,
    this.goodThermalHeadroom = 0.45,
    this.unstableEngineLoadMs = 90000,
    this.peakRssNearThresholdRatio = 0.85,
  });

  final int lowAvailableRamMb;
  final int highAvailableRamMb;
  final double lowDecodeChunksPerSecond;
  final double highDecodeChunksPerSecond;
  final double weakThermalHeadroom;
  final double goodThermalHeadroom;
  final int unstableEngineLoadMs;
  final double peakRssNearThresholdRatio;
}

class MemorySafetyConfig {
  const MemorySafetyConfig({
    this.maxFreeResourceFraction = 0.50,
    this.systemReserveMb = 1536,
    this.mediumRiskRatio = 0.70,
    this.highRiskRatio = 0.85,
  });

  final double maxFreeResourceFraction;
  final int systemReserveMb;
  final double mediumRiskRatio;
  final double highRiskRatio;

  double get availableFactor => maxFreeResourceFraction;

  /// min(availableRam * 0.50, totalRam - systemReserve).
  /// Null when either RAM figure was not probed.
  int? safeBudgetMb({required int? availableRamMb, required int? totalRamMb}) {
    if (availableRamMb == null || totalRamMb == null) {
      return null;
    }
    final fromAvailable = (availableRamMb * maxFreeResourceFraction).floor();
    final fromTotal = totalRamMb - systemReserveMb;
    if (fromTotal <= 0) {
      return fromAvailable;
    }
    return fromAvailable < fromTotal ? fromAvailable : fromTotal;
  }
}

class GenerationSampling {
  const GenerationSampling({
    required this.temperature,
    required this.topP,
    this.topKEnabled = false,
  });

  final double temperature;
  final double topP;

  /// Runtime reports max_top_k = 1. Keep the knob present and do not send topK > 1.
  final bool topKEnabled;

  static const structured = GenerationSampling(temperature: 0.1, topP: 0.85);
  static const normalQa = GenerationSampling(temperature: 0.4, topP: 0.90);
  static const detailed = GenerationSampling(temperature: 0.5, topP: 0.92);
  static const longForm = GenerationSampling(temperature: 0.6, topP: 0.95);

  static GenerationSampling forAnswerClass(String answerClass) {
    return switch (answerClass) {
      'long-form' => longForm,
      'detailed' => detailed,
      'medium' => normalQa,
      _ => structured,
    };
  }
}

class TierExecutionPolicy {
  const TierExecutionPolicy({
    required this.contextTokens,
    required this.shortOutput,
    required this.mediumOutput,
    required this.detailedOutput,
    required this.perStageOutput,
    required this.maxStages,
    required this.hardMaxStages,
    required this.maxElapsedMs,
    required this.multimodalRestricted,
    required this.maxImages,
    this.parallelInference = 1,
    this.residentModels = 1,
    this.benchmarkedContextTokens,
    this.minimumLeaseRemainingMs = 60000,
    this.minimumBatteryPercent = 20,
    this.maximumThermalState = ThermalState.warm,
  });

  final int contextTokens;
  final int shortOutput;
  final int mediumOutput;
  final int detailedOutput;
  final int perStageOutput;
  final int maxStages;
  final int hardMaxStages;
  final int maxElapsedMs;
  final bool multimodalRestricted;
  final int maxImages;
  final int parallelInference;
  final int residentModels;
  final int? benchmarkedContextTokens;
  final int minimumLeaseRemainingMs;
  final int minimumBatteryPercent;
  final ThermalState maximumThermalState;

  int outputFor(String answerClass) {
    return switch (answerClass) {
      'long-form' => perStageOutput,
      'detailed' => detailedOutput,
      'medium' => mediumOutput,
      _ => shortOutput,
    };
  }
}

class TierPolicyTable {
  const TierPolicyTable({
    this.t0 = const TierExecutionPolicy(
      contextTokens: 1024,
      shortOutput: 128,
      mediumOutput: 192,
      detailedOutput: 256,
      perStageOutput: 128,
      maxStages: 3,
      hardMaxStages: 4,
      maxElapsedMs: 8 * 60 * 1000,
      multimodalRestricted: true,
      maxImages: 0,
    ),
    this.t1 = const TierExecutionPolicy(
      contextTokens: 1536,
      shortOutput: 192,
      mediumOutput: 256,
      detailedOutput: 384,
      perStageOutput: 192,
      maxStages: 4,
      hardMaxStages: 6,
      maxElapsedMs: 12 * 60 * 1000,
      multimodalRestricted: true,
      maxImages: 0,
    ),
    this.t2 = const TierExecutionPolicy(
      contextTokens: 2048,
      shortOutput: 256,
      mediumOutput: 384,
      detailedOutput: 512,
      perStageOutput: 256,
      maxStages: 6,
      hardMaxStages: 8,
      maxElapsedMs: 16 * 60 * 1000,
      multimodalRestricted: false,
      maxImages: 1,
    ),
    this.t3 = const TierExecutionPolicy(
      contextTokens: 2048,
      shortOutput: 256,
      mediumOutput: 384,
      detailedOutput: 512,
      perStageOutput: 256,
      maxStages: 6,
      hardMaxStages: 8,
      maxElapsedMs: 20 * 60 * 1000,
      multimodalRestricted: false,
      maxImages: 1,
    ),
    this.t4 = const TierExecutionPolicy(
      contextTokens: 2048,
      shortOutput: 256,
      mediumOutput: 384,
      detailedOutput: 512,
      perStageOutput: 256,
      maxStages: 8,
      hardMaxStages: 10,
      maxElapsedMs: 25 * 60 * 1000,
      multimodalRestricted: false,
      maxImages: 1,
      benchmarkedContextTokens: 3072,
    ),
    this.t5 = const TierExecutionPolicy(
      contextTokens: 3072,
      shortOutput: 256,
      mediumOutput: 384,
      detailedOutput: 512,
      perStageOutput: 384,
      maxStages: 10,
      hardMaxStages: 12,
      maxElapsedMs: 25 * 60 * 1000,
      multimodalRestricted: false,
      maxImages: 1,
      benchmarkedContextTokens: 4096,
    ),
    this.promotedPerStageOutput = 384,
  });

  final TierExecutionPolicy t0;
  final TierExecutionPolicy t1;
  final TierExecutionPolicy t2;
  final TierExecutionPolicy t3;
  final TierExecutionPolicy t4;
  final TierExecutionPolicy t5;
  final int promotedPerStageOutput;

  TierExecutionPolicy get low => t0;
  TierExecutionPolicy get mid => t2;
  TierExecutionPolicy get high => t4;
  int get highPerStageWhenFast => promotedPerStageOutput;
  int get highHardMaxStagesWhenStable => t5.hardMaxStages;

  TierExecutionPolicy forHardware(HardwareTier tier) {
    return switch (tier) {
      HardwareTier.t0 => t0,
      HardwareTier.t1 => t1,
      HardwareTier.t2 => t2,
      HardwareTier.t3 => t3,
      HardwareTier.t4 => t4,
      HardwareTier.t5 => t5,
    };
  }

  TierExecutionPolicy forTier(String tierName) {
    return switch (tierName) {
      't0' || 'low' => t0,
      't1' => t1,
      't2' || 'mid' => t2,
      't3' => t3,
      't4' || 'high' => t4,
      't5' => t5,
      'unsupported' => t0,
      _ => t2,
    };
  }
}

/// ARM implementer 0x41 part IDs. Unknown parts are not guessed into a high class.
class ArmCpuPartTable {
  const ArmCpuPartTable();

  static const armImplementer = 0x41;

  static const classByPart = <int, CpuClass>{
    0xD03: CpuClass.c0, // Cortex-A53
    0xD04: CpuClass.c0, // Cortex-A35
    0xD05: CpuClass.c0, // Cortex-A55
    0xD07: CpuClass.c0, // Cortex-A57
    0xD46: CpuClass.c0, // Cortex-A510
    0xD80: CpuClass.c0, // Cortex-A520
    0xD09: CpuClass.c1, // Cortex-A73
    0xD0A: CpuClass.c1, // Cortex-A75
    0xD0B: CpuClass.c1, // Cortex-A76
    0xD0D: CpuClass.c2, // Cortex-A77
    0xD41: CpuClass.c2, // Cortex-A78
    0xD4B: CpuClass.c2, // Cortex-A78C
    0xD47: CpuClass.c2, // Cortex-A710
    0xD4D: CpuClass.c3, // Cortex-A715
    0xD44: CpuClass.c3, // Cortex-X1
    0xD48: CpuClass.c3, // Cortex-X2
    0xD81: CpuClass.c4, // Cortex-A720
    0xD87: CpuClass.c4, // Cortex-A725
    0xD4E: CpuClass.c4, // Cortex-X3
    0xD82: CpuClass.c4, // Cortex-X4
    0xD85: CpuClass.c4, // Cortex-X925
  };

  CpuClass? highestClass({
    required List<int> partIds,
    required List<int> implementerIds,
  }) {
    if (partIds.isEmpty) {
      return null;
    }
    final armOnly = implementerIds.isEmpty || implementerIds.contains(armImplementer);
    if (!armOnly) {
      return null;
    }
    CpuClass? highest;
    for (final part in partIds) {
      final cpuClass = classByPart[part];
      if (cpuClass == null) {
        continue;
      }
      if (highest == null || cpuClass.index > highest.index) {
        highest = cpuClass;
      }
    }
    return highest;
  }
}

