import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../runtime/device_snapshot.dart';

/// Platform bridge for foreground service, device probes, and signing material.
class WorkerRuntimeChannel {
  WorkerRuntimeChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('io.edgemint/worker_runtime');

  final MethodChannel _channel;

  Future<void> startForegroundService({required String assignmentId, required String taskType}) async {
    await _channel.invokeMethod<void>('startForegroundService', {
      'assignmentId': assignmentId,
      'taskType': taskType,
    });
  }

  Future<void> updateForegroundStatus({required int progressMilli, required String detail}) async {
    await _channel.invokeMethod<void>('updateForegroundStatus', {
      'progressMilli': progressMilli,
      'detail': detail,
    });
  }

  Future<void> stopForegroundService() async {
    await _channel.invokeMethod<void>('stopForegroundService');
  }

  Future<DeviceSnapshot> readDeviceSnapshot() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('readDeviceSnapshot');
    if (raw == null) {
      return _defaultSnapshot();
    }
    return _normalizeSnapshot(
      available: raw['available'] as bool? ?? true,
      batteryPercent: raw['batteryPercent'] as int? ?? 100,
      isCharging: raw['isCharging'] as bool? ?? false,
      isEmulator: raw['isEmulator'] as bool? ?? false,
      isX86Android: raw['isX86Android'] as bool? ?? false,
      thermalState: _thermal(raw['thermalState'] as String?),
      network: _network(raw['network'] as String?),
      freeStorageMb: raw['freeStorageMb'] as int? ?? 4096,
      withinSchedule: raw['withinSchedule'] as bool? ?? true,
      consentsGranted:
          (raw['consentsGranted'] as List<Object?>?)?.cast<String>() ?? const [],
    );
  }

  Future<void> setConsentsGranted(List<String> consents) async {
    await _channel.invokeMethod<void>('setConsentsGranted', consents);
  }

  Future<String?> localStorePath() async {
    return _channel.invokeMethod<String>('localStorePath');
  }

  DeviceSnapshot _normalizeSnapshot({
    required bool available,
    required int batteryPercent,
    required bool isCharging,
    required bool isEmulator,
    required bool isX86Android,
    required ThermalState thermalState,
    required NetworkKind network,
    required int freeStorageMb,
    required bool withinSchedule,
    required List<String> consentsGranted,
  }) {
    var emulator = isEmulator;
    var percent = batteryPercent;
    var charging = isCharging;
    if (kDebugMode && emulator) {
      percent = percent <= 0 ? 100 : percent;
      charging = true;
    }
    return DeviceSnapshot(
      available: available,
      batteryPercent: percent,
      isCharging: charging,
      isEmulator: emulator,
      isX86Android: isX86Android,
      thermalState: thermalState,
      network: network,
      freeStorageMb: freeStorageMb,
      withinSchedule: withinSchedule,
      consentsGranted: consentsGranted,
    );
  }

  Future<String> signingMaterial() async {
    final value = await _channel.invokeMethod<String>('signingMaterial');
    return value ?? 'test-signing-material';
  }

  Future<String?> importSideloadedModel({required String fileName}) async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('importSideloadedModel', {
      'fileName': fileName,
    });
    return raw?['path'] as String?;
  }

  Future<Uint8List> encryptLocal(Uint8List plaintext) async {
    final encoded = await _channel.invokeMethod<Uint8List>('encryptLocal', plaintext);
    return encoded ?? plaintext;
  }

  DeviceSnapshot _defaultSnapshot() {
    return const DeviceSnapshot(
      available: true,
      batteryPercent: 100,
      isCharging: false,
      thermalState: ThermalState.normal,
      network: NetworkKind.wifi,
      freeStorageMb: 4096,
      withinSchedule: true,
      consentsGranted: ['terms', 'privacy', 'resource_use', 'reward_disclosure'],
    );
  }

  ThermalState _thermal(String? value) {
    return switch (value) {
      'warm' => ThermalState.warm,
      'throttled' => ThermalState.throttled,
      'critical' => ThermalState.critical,
      _ => ThermalState.normal,
    };
  }

  NetworkKind _network(String? value) {
    return switch (value) {
      'wifi' => NetworkKind.wifi,
      'cellular' => NetworkKind.cellular,
      'offline' => NetworkKind.offline,
      _ => NetworkKind.unknown,
    };
  }
}

class NoopWorkerRuntimeChannel extends WorkerRuntimeChannel {
  NoopWorkerRuntimeChannel({this.snapshot = const DeviceSnapshot(
    available: true,
    batteryPercent: 100,
    isCharging: true,
    thermalState: ThermalState.normal,
    network: NetworkKind.wifi,
    freeStorageMb: 8192,
    withinSchedule: true,
    consentsGranted: ['terms', 'privacy', 'resource_use', 'reward_disclosure'],
  ), this.material = 'test-signing-material'});

  final DeviceSnapshot snapshot;
  final String material;

  @override
  Future<DeviceSnapshot> readDeviceSnapshot() async => snapshot;

  @override
  Future<String> signingMaterial() async => material;

  @override
  Future<String?> importSideloadedModel({required String fileName}) async => null;

  @override
  Future<void> startForegroundService({required String assignmentId, required String taskType}) async {}

  @override
  Future<void> updateForegroundStatus({required int progressMilli, required String detail}) async {}

  @override
  Future<void> stopForegroundService() async {}

  @override
  Future<Uint8List> encryptLocal(Uint8List plaintext) async => plaintext;
}
