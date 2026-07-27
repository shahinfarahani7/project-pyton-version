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
  });

  final bool available;
  final int batteryPercent;
  final bool isCharging;
  final ThermalState thermalState;
  final NetworkKind network;
  final int freeStorageMb;
  final bool withinSchedule;
  final List<String> consentsGranted;

  DeviceSnapshot copyWith({
    bool? available,
    int? batteryPercent,
    bool? isCharging,
    ThermalState? thermalState,
    NetworkKind? network,
    int? freeStorageMb,
    bool? withinSchedule,
    List<String>? consentsGranted,
  }) {
    return DeviceSnapshot(
      available: available ?? this.available,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      isCharging: isCharging ?? this.isCharging,
      thermalState: thermalState ?? this.thermalState,
      network: network ?? this.network,
      freeStorageMb: freeStorageMb ?? this.freeStorageMb,
      withinSchedule: withinSchedule ?? this.withinSchedule,
      consentsGranted: consentsGranted ?? this.consentsGranted,
    );
  }
}
