import 'worker_process_memory_telemetry.dart';

enum ThermalState { normal, warm, throttled, critical }

enum NetworkKind { wifi, cellular, offline, unknown }

class DeviceSnapshot {
  const DeviceSnapshot({
    required this.available,
    required this.batteryPercent,
    required this.isCharging,
    required this.thermalState,
    required this.network,
    required this.freeStorageMb,
    required this.withinSchedule,
    required this.consentsGranted,
    this.isEmulator = false,
    this.isX86Android = false,
    this.deviceTotalRamMb,
    this.deviceAvailableRamMb,
    this.lowMemoryThresholdMb,
    this.lowMemory,
    this.cpuCoreCount,
    this.cpuArchitecture,
    this.cpuAbi,
    this.cpuPartIds = const [],
    this.cpuImplementerIds = const [],
    this.perCoreMaxFrequencyMHz = const [],
    this.highestCoreMaxFrequencyMHz,
    this.performanceCoreCount,
    this.efficiencyCoreCount,
    this.processPssKb,
    this.processPrivateDirtyKb,
    this.javaHeapKb,
    this.nativeHeapKb,
  });

  final bool available;
  final int batteryPercent;
  final bool isCharging;
  final bool isEmulator;
  final bool isX86Android;
  final ThermalState thermalState;
  final NetworkKind network;
  final int freeStorageMb;
  final bool withinSchedule;
  final List<String> consentsGranted;
  final int? deviceTotalRamMb;
  final int? deviceAvailableRamMb;
  final int? lowMemoryThresholdMb;
  final bool? lowMemory;
  final int? cpuCoreCount;
  final String? cpuArchitecture;
  final String? cpuAbi;
  final List<int> cpuPartIds;
  final List<int> cpuImplementerIds;
  final List<int> perCoreMaxFrequencyMHz;
  final int? highestCoreMaxFrequencyMHz;
  final int? performanceCoreCount;
  final int? efficiencyCoreCount;
  final int? processPssKb;
  final int? processPrivateDirtyKb;
  final int? javaHeapKb;
  final int? nativeHeapKb;

  ProcessMemorySnapshot toProcessMemorySnapshot() {
    return ProcessMemorySnapshot(
      deviceTotalRamMb: deviceTotalRamMb,
      deviceAvailableRamMb: deviceAvailableRamMb,
      lowMemory: lowMemory,
      processPssKb: processPssKb,
      processPrivateDirtyKb: processPrivateDirtyKb,
      javaHeapKb: javaHeapKb,
      nativeHeapKb: nativeHeapKb,
    );
  }

  DeviceSnapshot copyWith({
    bool? available,
    int? batteryPercent,
    bool? isCharging,
    ThermalState? thermalState,
    NetworkKind? network,
    int? freeStorageMb,
    bool? withinSchedule,
    List<String>? consentsGranted,
    bool? isEmulator,
    bool? isX86Android,
    int? deviceTotalRamMb,
    int? deviceAvailableRamMb,
    int? lowMemoryThresholdMb,
    bool? lowMemory,
    int? cpuCoreCount,
    String? cpuArchitecture,
    String? cpuAbi,
    List<int>? cpuPartIds,
    List<int>? cpuImplementerIds,
    List<int>? perCoreMaxFrequencyMHz,
    int? highestCoreMaxFrequencyMHz,
    int? performanceCoreCount,
    int? efficiencyCoreCount,
  }) {
    return DeviceSnapshot(
      available: available ?? this.available,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      isCharging: isCharging ?? this.isCharging,
      isEmulator: isEmulator ?? this.isEmulator,
      isX86Android: isX86Android ?? this.isX86Android,
      thermalState: thermalState ?? this.thermalState,
      network: network ?? this.network,
      freeStorageMb: freeStorageMb ?? this.freeStorageMb,
      withinSchedule: withinSchedule ?? this.withinSchedule,
      consentsGranted: consentsGranted ?? this.consentsGranted,
      deviceTotalRamMb: deviceTotalRamMb ?? this.deviceTotalRamMb,
      deviceAvailableRamMb: deviceAvailableRamMb ?? this.deviceAvailableRamMb,
      lowMemoryThresholdMb: lowMemoryThresholdMb ?? this.lowMemoryThresholdMb,
      lowMemory: lowMemory ?? this.lowMemory,
      cpuCoreCount: cpuCoreCount ?? this.cpuCoreCount,
      cpuArchitecture: cpuArchitecture ?? this.cpuArchitecture,
      cpuAbi: cpuAbi ?? this.cpuAbi,
      cpuPartIds: cpuPartIds ?? this.cpuPartIds,
      cpuImplementerIds: cpuImplementerIds ?? this.cpuImplementerIds,
      perCoreMaxFrequencyMHz: perCoreMaxFrequencyMHz ?? this.perCoreMaxFrequencyMHz,
      highestCoreMaxFrequencyMHz:
          highestCoreMaxFrequencyMHz ?? this.highestCoreMaxFrequencyMHz,
      performanceCoreCount: performanceCoreCount ?? this.performanceCoreCount,
      efficiencyCoreCount: efficiencyCoreCount ?? this.efficiencyCoreCount,
      processPssKb: processPssKb,
      processPrivateDirtyKb: processPrivateDirtyKb,
      javaHeapKb: javaHeapKb,
      nativeHeapKb: nativeHeapKb,
    );
  }
}
