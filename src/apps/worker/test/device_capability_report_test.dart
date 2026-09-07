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
  });
}
