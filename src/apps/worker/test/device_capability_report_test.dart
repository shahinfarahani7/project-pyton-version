import 'package:edgemint_worker/runtime/device_capability_report.dart';
import 'package:edgemint_worker/runtime/device_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('device capability report includes runtime classes and telemetry', () {
    const snapshot = DeviceSnapshot(
      available: true,
      batteryPercent: 78,
      isCharging: true,
      thermalState: ThermalState.normal,
      network: NetworkKind.wifi,
      freeStorageMb: 20480,
      withinSchedule: true,
      consentsGranted: ['terms'],
    );

    final report = DeviceCapabilityReport.build(
      snapshot: snapshot,
      taskCapabilities: const ['ocr.extract_text.v1', 'text.summarize.v1'],
    );

    expect(report['deviceTier'], 'T4');
    expect(report['runtimeClasses'], contains('mediapipe_llm'));
    expect(report['runtimeClasses'], contains('paddle_ocr'));
    expect(report['battery'], {'levelBps': 7800, 'charging': true});
    expect(report['network'], {'type': 'wifi'});
    expect(report['storage']['availableBytes'], 20480 * 1024 * 1024);
    expect(report.containsKey('device'), isFalse);
  });

  test('device capability report carries device identity and hardware', () {
    const snapshot = DeviceSnapshot(
      available: true,
      batteryPercent: 50,
      isCharging: false,
      thermalState: ThermalState.normal,
      network: NetworkKind.wifi,
      freeStorageMb: 1024,
      withinSchedule: true,
      consentsGranted: ['terms'],
      deviceManufacturer: 'samsung',
      deviceModel: 'SM-S928B',
      deviceName: '  Galaxy S24 Ultra ',
      cpuCoreCount: 8,
      deviceTotalRamMb: 11811,
    );

    final report = DeviceCapabilityReport.build(
      snapshot: snapshot,
      taskCapabilities: const ['text.summarize.v1'],
    );

    expect(report['device'], {
      'manufacturer': 'samsung',
      'model': 'SM-S928B',
      'name': 'Galaxy S24 Ultra',
      'cpuCoreCount': 8,
      'totalRamBytes': 11811 * 1024 * 1024,
    });
    expect(report['resourceVector']['cpuUnits'], 100);
  });
}
