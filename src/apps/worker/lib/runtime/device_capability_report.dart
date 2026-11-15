import '../runtime/device_snapshot.dart';
import '../tasks/mobile_task_dispatcher.dart';
import 'device_inference_policy_config.dart';
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
    int? totalRamBytes,
    int? availableRamBytes,
    int safetyReserveBytes = 536870912,
    int maxAiStorageBytes = 5368709120,
    int minimumFreeBytes = 1073741824,
    int cpuUnits = 100,
    int? memoryBytes,
    int modelSessionUnits = 2,
  }) {
    final freeStorageBytes = snapshot.freeStorageMb * 1024 * 1024;
    final probedTotalMb = snapshot.deviceTotalRamMb;
    final probedAvailableMb = snapshot.deviceAvailableRamMb;
    final totalBytes = totalRamBytes ??
        (probedTotalMb != null && probedTotalMb > 0
            ? probedTotalMb * 1024 * 1024
            : null);
    final availableBytes = availableRamBytes ??
        (probedAvailableMb != null && probedAvailableMb >= 0
            ? probedAvailableMb * 1024 * 1024
            : null);
    final measured = totalBytes != null && availableBytes != null;
    final int? budgetMb;
    if (totalBytes != null && availableBytes != null) {
      budgetMb = const MemorySafetyConfig().safeBudgetMb(
        availableRamMb: availableBytes ~/ (1024 * 1024),
        totalRamMb: totalBytes ~/ (1024 * 1024),
      );
    } else {
      budgetMb = null;
    }
    final processPssBytes = snapshot.processPssKb == null
        ? null
        : snapshot.processPssKb! * 1024;
    final runtimeClasses = RuntimeClassCatalog.fromTaskCapabilities(taskCapabilities);
    final device = _device(snapshot);

    return {
      if (device.isNotEmpty) 'device': device,
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
        if ((memoryBytes ?? totalBytes) != null)
          'memoryBytes': memoryBytes ?? totalBytes,
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
        'attribution': measured ? 'measured' : 'unknown',
        if (totalBytes != null) 'totalRamBytes': totalBytes,
        if (availableBytes != null) 'availableBytes': availableBytes,
        'safetyReserveBytes': safetyReserveBytes,
        if (budgetMb != null) 'memoryBudgetBytes': budgetMb * 1024 * 1024,
        if (processPssBytes != null) 'processPssBytes': processPssBytes,
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

  static Map<String, dynamic> _device(DeviceSnapshot snapshot) {
    String? text(String? value, int maxLength) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isEmpty) return null;
      return trimmed.length > maxLength ? trimmed.substring(0, maxLength) : trimmed;
    }

    final manufacturer = text(snapshot.deviceManufacturer, 64);
    final model = text(snapshot.deviceModel, 64);
    final name = text(snapshot.deviceName, 128);
    final cores = snapshot.cpuCoreCount;
    final totalRamMb = snapshot.deviceTotalRamMb;
    return {
      'manufacturer': ?manufacturer,
      'model': ?model,
      'name': ?name,
      if (cores != null && cores > 0) 'cpuCoreCount': cores,
      if (totalRamMb != null && totalRamMb > 0) 'totalRamBytes': totalRamMb * 1024 * 1024,
    };
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
