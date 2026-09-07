import '../runtime/device_snapshot.dart';
import '../tasks/mobile_task_dispatcher.dart';
import 'runtime_class_catalog.dart';

/// Builds a DeviceCapability report payload aligned with
/// dsl/schemas/devicecapability.schema.json (spec section).
abstract final class DeviceCapabilityReport {
  static Map<String, dynamic> build({
    required DeviceSnapshot snapshot,
    required Iterable<String> taskCapabilities,
    String platformOs = 'android',
    String abi = 'arm64-v8a',
    int? apiLevel,
    int pageSizeKb = 16,
    String deviceTier = 'T4',
    String regionCode = 'US',
    String runtimeAbi = 'mediapipe-llm-v1',
    int totalRamBytes = 8589934592,
    int safetyReserveBytes = 536870912,
    int maxAiStorageBytes = 5368709120,
    int minimumFreeBytes = 1073741824,
    int cpuUnits = 100,
    int memoryBytes = 8589934592,
    int modelSessionUnits = 2,
  }) {
    final freeStorageBytes = snapshot.freeStorageMb * 1024 * 1024;
    final availableRamBytes = (totalRamBytes * 0.67).round();
    final runtimeClasses = RuntimeClassCatalog.fromTaskCapabilities(taskCapabilities);

    return {
      'platform': {
        'os': platformOs,
        'abi': abi,
        if (apiLevel != null) 'apiLevel': apiLevel,
        'pageSizeKb': pageSizeKb,
      },
      'deviceTier': deviceTier,
      'regionCode': regionCode,
      'runtimeAbi': runtimeAbi,
      'resourceVector': {
        'cpuUnits': cpuUnits,
        'memoryBytes': memoryBytes,
        'storageBytes': freeStorageBytes,
        'acceleratorUnits': 0,
        'modelSessionUnits': modelSessionUnits,
      },
      'runtimeClasses': runtimeClasses,
      'storage': {
        'availableBytes': freeStorageBytes,
        'minimumFreeBytes': minimumFreeBytes,
        'maxAiStorageBytes': maxAiStorageBytes,
      },
      'memory': {
        'totalRamBytes': totalRamBytes,
        'availableBytes': availableRamBytes,
        'safetyReserveBytes': safetyReserveBytes,
      },
      'thermal': {
        'state': _thermalState(snapshot.thermalState),
      },
      'battery': {
        'levelBps': snapshot.batteryPercent * 100,
        'charging': snapshot.isCharging,
      },
      'network': {
        'type': _networkType(snapshot.network),
      },
    };
  }

  static Map<String, dynamic> fromDispatcher({
    required DeviceSnapshot snapshot,
    MobileTaskDispatcher? dispatcher,
    String platformOs = 'android',
    String abi = 'arm64-v8a',
  }) {
    final taskDispatcher = dispatcher ?? MobileTaskDispatcher();
    return build(
      snapshot: snapshot,
      taskCapabilities: taskDispatcher.capabilities,
      platformOs: platformOs,
      abi: abi,
    );
  }

  static String _thermalState(ThermalState state) => switch (state) {
        ThermalState.normal => 'nominal',
        ThermalState.warm => 'fair',
        ThermalState.throttled => 'serious',
        ThermalState.critical => 'critical',
      };

  static String _networkType(NetworkKind network) => switch (network) {
        NetworkKind.wifi => 'wifi',
        NetworkKind.cellular => 'cellular',
        NetworkKind.offline => 'offline',
        NetworkKind.unknown => 'wifi',
      };
}
