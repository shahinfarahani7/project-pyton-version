import 'device_snapshot.dart';
import 'device_inference_policy_config.dart';

enum DeviceTier { low, mid, high, unsupported }

/// Measurements from a controlled model benchmark. Missing samples stay null.
class DeviceBenchmarkMetrics {
  const DeviceBenchmarkMetrics({
    this.engineLoadMs,
    this.ttfcMs,
    this.decodeChunksPerSecond,
    this.peakRssMb,
    this.sustainedDecodeChunksPerSecond,
    this.thermalDeltaC,
    this.batteryDrainPercent,
    this.engineLoadFailed = false,
    this.lowMemoryOrLmk = false,
    this.nativeOom = false,
    this.repeatedInferenceCrash = false,
    this.thermalCritical = false,
    this.contextTokens,
    this.modelSha256,
  });

  final int? engineLoadMs;
  final int? ttfcMs;
  final double? decodeChunksPerSecond;
  final int? peakRssMb;
  final double? sustainedDecodeChunksPerSecond;
  final double? thermalDeltaC;
  final double? batteryDrainPercent;
  final bool engineLoadFailed;
  final bool lowMemoryOrLmk;
  final bool nativeOom;
  final bool repeatedInferenceCrash;
  final bool thermalCritical;
  final int? contextTokens;
  final String? modelSha256;

  bool get succeeded =>
      !engineLoadFailed &&
      !lowMemoryOrLmk &&
      !nativeOom &&
      !repeatedInferenceCrash &&
      !thermalCritical &&
      engineLoadMs != null;

  bool succeededForContext(int contextTokens) =>
      succeeded && this.contextTokens == contextTokens;
}

/// Immutable device facts collected at startup. Unknown probes stay null.
class DeviceCapabilityProfile {
  const DeviceCapabilityProfile({
    this.deviceId,
    this.manufacturer,
    this.model,
    this.androidVersion,
    this.abi,
    this.totalRamMb,
    this.availableRamMb,
    this.lowMemoryThresholdMb,
    this.cpuCoreCount,
    this.cpuArchitecture,
    this.cpuAbi,
    this.cpuPartIds = const [],
    this.cpuImplementerIds = const [],
    this.perCoreMaxFrequencyMHz = const [],
    this.highestCoreMaxFrequencyMHz,
    this.performanceCoreCount,
    this.efficiencyCoreCount,
    this.isLowMemory,
    this.gpuAvailable,
    this.gpuBackend,
    this.gpuRenderer,
    this.gpuVendor,
    this.npuAvailable,
    this.supportedAccelerators = const [],
    this.batteryPercent,
    this.isCharging,
    this.batteryTemperatureC,
    this.thermalState,
    this.thermalHeadroom,
    this.freeStorageMb,
    this.benchmark,
  });

  final String? deviceId;
  final String? manufacturer;
  final String? model;
  final String? androidVersion;
  final String? abi;
  final int? totalRamMb;
  final int? availableRamMb;
  final int? lowMemoryThresholdMb;
  final int? cpuCoreCount;
  final String? cpuArchitecture;
  final String? cpuAbi;
  final List<int> cpuPartIds;
  final List<int> cpuImplementerIds;
  final List<int> perCoreMaxFrequencyMHz;
  final int? highestCoreMaxFrequencyMHz;
  final int? performanceCoreCount;
  final int? efficiencyCoreCount;
  final bool? isLowMemory;
  final bool? gpuAvailable;
  final String? gpuBackend;
  final String? gpuRenderer;
  final String? gpuVendor;
  final bool? npuAvailable;
  final List<String> supportedAccelerators;
  final int? batteryPercent;
  final bool? isCharging;
  final double? batteryTemperatureC;
  final ThermalState? thermalState;
  final double? thermalHeadroom;
  final int? freeStorageMb;
  final DeviceBenchmarkMetrics? benchmark;

  static String display(Object? value) => value == null ? 'unknown' : '$value';

  String get fingerprint => [
        display(manufacturer),
        display(model),
        display(androidVersion),
        display(abi),
        display(totalRamMb),
      ].join('|');

  DeviceTier get tier => DeviceTierClassifier.classify(this);

  RamTier get ramTier => DeviceTierClassifier.ramTier(this);

  CpuClass get cpuClass => DeviceTierClassifier.cpuClass(this);

  HardwareTier get cpuTier => DeviceTierClassifier.cpuTier(this);

  HardwareTier get hardwareTier => DeviceTierClassifier.finalTier(this);

  int? get cpuImplementer =>
      cpuImplementerIds.isEmpty ? null : cpuImplementerIds.first;

  int? get cpuMaxFrequencyMHz => highestCoreMaxFrequencyMHz;

  double? get thermalDelta => benchmark?.thermalDeltaC;

  String hardwareLog() =>
      '[DEVICE HARDWARE] totalRamMb=${display(totalRamMb)} '
      'availableRamMb=${display(availableRamMb)} '
      'ram=${display(totalRamMb)} '
      'ramTier=${ramTier.name.toUpperCase()} '
      'cpuArchitecture=${display(cpuArchitecture)} '
      'cpuCoreCount=${display(cpuCoreCount)} '
      'cpuPartIds=${cpuPartIds.isEmpty ? 'unknown' : cpuPartIds.map((part) => '0x${part.toRadixString(16)}').join(',')} '
      'cpuParts=${cpuPartIds.isEmpty ? 'unknown' : cpuPartIds.map((part) => '0x${part.toRadixString(16)}').join(',')} '
      'cpuMaxMHz=${display(cpuMaxFrequencyMHz)} '
      'frequency=${display(cpuMaxFrequencyMHz)} '
      'performanceCores=${display(performanceCoreCount)} '
      'cpuClass=${cpuClass.name}';

  String tierLog() =>
      '[DEVICE TIER] ramTier=${ramTier.name.toUpperCase()} '
      'cpuTier=${cpuTier.name.toUpperCase()} '
      'finalTier=${hardwareTier.name.toUpperCase()} '
      'reason=${DeviceTierClassifier.reason(this)}';

  String lookupLog() =>
      '[DEVICE LOOKUP] ramTier=${ramTier.name.toUpperCase()} '
      'cpuTier=${cpuTier.name.toUpperCase()} '
      'finalTier=${hardwareTier.name.toUpperCase()} '
      'reason=${DeviceTierClassifier.reason(this)}';

  String get deviceLabel => model ?? manufacturer ?? deviceId ?? 'unknown';

  String get gpuLabel {
    if (gpuAvailable == false) {
      return 'none';
    }
    final backend = gpuBackend;
    if (backend == null || backend.isEmpty) {
      return gpuAvailable == true ? 'unknown' : 'unknown';
    }
    return backend;
  }

  String profileLog() =>
      '[DEVICE PROFILE] device=$deviceLabel tier=${tier.name.toUpperCase()} '
      'totalRamMb=${display(totalRamMb)} availableRamMb=${display(availableRamMb)} '
      'gpu=$gpuLabel thermal=${thermalState?.name ?? 'unknown'}';

  /// Recorded Samsung SM-A536E baseline. Identity fields are the known device;
  /// decode is the observed chunk rate, not a name-based guess.
  factory DeviceCapabilityProfile.a53Baseline() {
    return const DeviceCapabilityProfile(
      manufacturer: 'Samsung',
      model: 'SM-A536E',
      androidVersion: '14',
      abi: 'arm64-v8a',
      totalRamMb: 6144,
      availableRamMb: 3072,
      lowMemoryThresholdMb: 800,
      cpuCoreCount: 8,
      cpuArchitecture: 'arm64-v8a',
      cpuAbi: 'arm64-v8a',
      cpuPartIds: [0xD05, 0xD41],
      cpuImplementerIds: [0x41],
      highestCoreMaxFrequencyMHz: 2400,
      performanceCoreCount: 2,
      efficiencyCoreCount: 6,
      gpuAvailable: true,
      gpuBackend: 'OpenCL',
      npuAvailable: false,
      supportedAccelerators: ['GPU'],
      batteryPercent: 60,
      isCharging: false,
      thermalState: ThermalState.normal,
      thermalHeadroom: 0.35,
      freeStorageMb: 8192,
      benchmark: DeviceBenchmarkMetrics(
        engineLoadMs: 42000,
        ttfcMs: 1800,
        decodeChunksPerSecond: 2.3,
        peakRssMb: 1500,
        sustainedDecodeChunksPerSecond: 2.1,
        contextTokens: 2048,
        modelSha256: '4912bb5a9c30993c51a7711f763212077458529312175df0573a78323a2bb7ff',
      ),
    );
  }

  /// Copies probed snapshot fields only. Unprobed GPU, NPU, and CPU stay null.
  factory DeviceCapabilityProfile.fromSnapshot(
    DeviceSnapshot snapshot, {
    DeviceBenchmarkMetrics? benchmark,
    String? deviceId,
    String? manufacturer,
    String? model,
    String? androidVersion,
    String? abi,
  }) {
    return DeviceCapabilityProfile(
      deviceId: deviceId,
      manufacturer: manufacturer,
      model: model,
      androidVersion: androidVersion,
      abi: abi,
      totalRamMb: snapshot.deviceTotalRamMb,
      availableRamMb: snapshot.deviceAvailableRamMb,
      lowMemoryThresholdMb: snapshot.lowMemoryThresholdMb,
      isLowMemory: snapshot.lowMemory,
      cpuCoreCount: snapshot.cpuCoreCount,
      cpuArchitecture: snapshot.cpuArchitecture,
      cpuAbi: snapshot.cpuAbi,
      cpuPartIds: snapshot.cpuPartIds,
      cpuImplementerIds: snapshot.cpuImplementerIds,
      perCoreMaxFrequencyMHz: snapshot.perCoreMaxFrequencyMHz,
      highestCoreMaxFrequencyMHz: snapshot.highestCoreMaxFrequencyMHz,
      performanceCoreCount: snapshot.performanceCoreCount,
      efficiencyCoreCount: snapshot.efficiencyCoreCount,
      batteryPercent: snapshot.batteryPercent,
      isCharging: snapshot.isCharging,
      thermalState: snapshot.thermalState,
      freeStorageMb: snapshot.freeStorageMb,
      benchmark: benchmark,
    );
  }

  DeviceCapabilityProfile copyWith({
    int? availableRamMb,
    int? batteryPercent,
    bool? isCharging,
    ThermalState? thermalState,
    double? thermalHeadroom,
    DeviceBenchmarkMetrics? benchmark,
  }) {
    return DeviceCapabilityProfile(
      deviceId: deviceId,
      manufacturer: manufacturer,
      model: model,
      androidVersion: androidVersion,
      abi: abi,
      totalRamMb: totalRamMb,
      availableRamMb: availableRamMb ?? this.availableRamMb,
      lowMemoryThresholdMb: lowMemoryThresholdMb,
      cpuCoreCount: cpuCoreCount,
      cpuArchitecture: cpuArchitecture,
      cpuAbi: cpuAbi,
      cpuPartIds: cpuPartIds,
      cpuImplementerIds: cpuImplementerIds,
      perCoreMaxFrequencyMHz: perCoreMaxFrequencyMHz,
      highestCoreMaxFrequencyMHz: highestCoreMaxFrequencyMHz,
      performanceCoreCount: performanceCoreCount,
      efficiencyCoreCount: efficiencyCoreCount,
      isLowMemory: isLowMemory,
      gpuAvailable: gpuAvailable,
      gpuBackend: gpuBackend,
      gpuRenderer: gpuRenderer,
      gpuVendor: gpuVendor,
      npuAvailable: npuAvailable,
      supportedAccelerators: supportedAccelerators,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      isCharging: isCharging ?? this.isCharging,
      batteryTemperatureC: batteryTemperatureC,
      thermalState: thermalState ?? this.thermalState,
      thermalHeadroom: thermalHeadroom ?? this.thermalHeadroom,
      freeStorageMb: freeStorageMb,
      benchmark: benchmark ?? this.benchmark,
    );
  }
}

/// Final tier is the weaker of RAM tier and the CPU class ceiling.
/// Available RAM is a safety budget, not a capability tier. Phone model is not an input.
abstract final class DeviceTierClassifier {
  static DeviceTier classify(DeviceCapabilityProfile profile) {
    final benchmark = profile.benchmark;
    if (benchmark != null &&
        (benchmark.engineLoadFailed ||
            benchmark.nativeOom ||
            benchmark.repeatedInferenceCrash ||
            benchmark.thermalCritical)) {
      return DeviceTier.unsupported;
    }
    return legacyTier(finalTier(profile));
  }

  static DeviceTier legacyTier(HardwareTier tier) {
    return switch (tier) {
      HardwareTier.t0 || HardwareTier.t1 => DeviceTier.low,
      HardwareTier.t2 || HardwareTier.t3 => DeviceTier.mid,
      HardwareTier.t4 || HardwareTier.t5 => DeviceTier.high,
    };
  }

  static RamTier ramTier(DeviceCapabilityProfile profile) =>
      RamTierClassifier.classify(profile);

  static CpuClass cpuClass(
    DeviceCapabilityProfile profile, {
    ArmCpuPartTable parts = const ArmCpuPartTable(),
  }) =>
      CpuClassClassifier.classify(profile, parts: parts);

  static HardwareTier cpuTier(DeviceCapabilityProfile profile) =>
      CpuClassClassifier.tier(cpuClass(profile));

  static HardwareTier finalTier(DeviceCapabilityProfile profile) =>
      DeviceTierLookup.lookup(profile);

  static String reason(DeviceCapabilityProfile profile) {
    return 'ram=${ramTier(profile).name.toUpperCase()} '
        'cpuClass=${cpuClass(profile).name} '
        'cpuTier=${cpuTier(profile).name.toUpperCase()} '
        'final=${finalTier(profile).name.toUpperCase()}';
  }
}

/// Reads the snapshot produced by Android MemoryInfo and /proc/cpuinfo.
abstract final class DeviceCapabilityCollector {
  static DeviceCapabilityProfile collect(
    DeviceSnapshot snapshot, {
    DeviceBenchmarkMetrics? benchmark,
  }) {
    return DeviceCapabilityProfile.fromSnapshot(snapshot, benchmark: benchmark);
  }
}

/// Total RAM bands. 1024MB = 1GB. Unknown total RAM stays T1.
abstract final class RamTierClassifier {
  static const gib = 1024;

  static RamTier classify(DeviceCapabilityProfile profile) =>
      fromTotalMb(profile.totalRamMb);

  static RamTier fromTotalMb(int? totalRamMb) {
    final total = totalRamMb;
    if (total == null) {
      return RamTier.t1;
    }
    if (total < 4 * gib) {
      return RamTier.t0;
    }
    if (total < 6 * gib) {
      return RamTier.t1;
    }
    if (total < 8 * gib) {
      return RamTier.t2;
    }
    if (total < 12 * gib) {
      return RamTier.t3;
    }
    if (total < 16 * gib) {
      return RamTier.t4;
    }
    return RamTier.t5;
  }

  static HardwareTier asHardware(RamTier tier) => HardwareTier.values[tier.index];
}

/// ARM part class, with a conservative frequency fallback that never exceeds class 1.
abstract final class CpuClassClassifier {
  static CpuClass classify(
    DeviceCapabilityProfile profile, {
    ArmCpuPartTable parts = const ArmCpuPartTable(),
  }) {
    final fromParts = parts.highestClass(
      partIds: profile.cpuPartIds,
      implementerIds: profile.cpuImplementerIds,
    );
    if (fromParts != null) {
      return fromParts;
    }
    return _frequencyFallback(profile);
  }

  /// Ceiling of the class band. min(ram, this) produces the lower end of C0→T0/T1.
  static HardwareTier tier(CpuClass cpu) {
    return switch (cpu) {
      CpuClass.c0 => HardwareTier.t1,
      CpuClass.c1 => HardwareTier.t2,
      CpuClass.c2 => HardwareTier.t3,
      CpuClass.c3 => HardwareTier.t4,
      CpuClass.c4 => HardwareTier.t5,
      CpuClass.unknown => HardwareTier.t2,
    };
  }

  static CpuClass _frequencyFallback(DeviceCapabilityProfile profile) {
    final cores = profile.cpuCoreCount;
    final mhz = profile.cpuMaxFrequencyMHz;
    final performance = profile.performanceCoreCount;
    if (cores == null && mhz == null) {
      return CpuClass.unknown;
    }
    if (mhz != null && mhz >= 2400 && (cores ?? 0) >= 8 && (performance ?? 0) >= 1) {
      return CpuClass.c1;
    }
    if ((cores ?? 0) >= 4) {
      return CpuClass.c0;
    }
    return CpuClass.unknown;
  }
}

/// finalTier = min(ramTier, cpuTier). Available RAM does not change this tier.
abstract final class DeviceTierLookup {
  static HardwareTier lookup(DeviceCapabilityProfile profile) {
    return resolve(
      totalRamMb: profile.totalRamMb,
      cpuClass: CpuClassClassifier.classify(profile),
    );
  }

  /// The only capability inputs are total RAM and CPU class.
  static HardwareTier resolve({
    required int? totalRamMb,
    required CpuClass cpuClass,
  }) {
    final ram = RamTierClassifier.asHardware(RamTierClassifier.fromTotalMb(totalRamMb));
    final cpu = CpuClassClassifier.tier(cpuClass);
    return ram.index <= cpu.index ? ram : cpu;
  }

  static TierExecutionPolicy policy({
    required int? totalRamMb,
    required CpuClass cpuClass,
    TierPolicyTable table = const TierPolicyTable(),
  }) {
    return table.forHardware(resolve(totalRamMb: totalRamMb, cpuClass: cpuClass));
  }
}
