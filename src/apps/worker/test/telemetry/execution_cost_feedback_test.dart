import 'package:edgemint_worker/runtime/device_snapshot.dart';
import 'package:edgemint_worker/telemetry/execution_cost_feedback.dart';
import 'package:edgemint_worker/telemetry/resource_envelope_catalog.dart';
import 'package:edgemint_worker/telemetry/worker_task_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resource envelope catalog scales LLM tasks by input size', () {
    final small = ResourceEnvelopeCatalog.scaledForInput(
      taskType: 'text.summarize',
      inputBytes: 1024,
    );
    final large = ResourceEnvelopeCatalog.scaledForInput(
      taskType: 'text.summarize',
      inputBytes: 4 * 1024 * 1024,
    );

    expect(large.durationMs, greaterThan(small.durationMs));
    expect(large.peakMemoryBytes, greaterThan(small.peakMemoryBytes));
  });

  test('execution cost feedback builder emits predicted vs observed sample', () {
    final builder = ExecutionCostFeedbackBuilder(
      taskType: 'text.summarize',
      inputBytes: 256 * 1024,
      startSnapshot: const DeviceSnapshot(
        available: true,
        batteryPercent: 80,
        isCharging: true,
        thermalState: ThermalState.normal,
        network: NetworkKind.wifi,
        freeStorageMb: 4096,
        withinSchedule: true,
        consentsGranted: ['compute'],
      ),
      cpuAverageBps: 2100,
    );
    final metrics = WorkerTaskMetrics(startedAt: DateTime.now().subtract(const Duration(seconds: 64)))
      ..llmMs = 60000
      ..inputBytes = 256 * 1024
      ..peakMemoryMb = 1750;

    final feedback = builder.build(
      metrics: metrics,
      endSnapshot: const DeviceSnapshot(
        available: true,
        batteryPercent: 78,
        isCharging: true,
        thermalState: ThermalState.warm,
        network: NetworkKind.wifi,
        freeStorageMb: 4096,
        withinSchedule: true,
        consentsGranted: ['compute'],
      ),
    );

    expect(feedback.predicted.cpuUnits, greaterThan(0));
    expect(feedback.observed.durationMs, greaterThan(0));
    expect(feedback.observed.thermalDeltaBps, 2500);
    expect(feedback.observed.throughputUnit, 'tokens');
    expect(feedback.variance.durationMs, feedback.observed.durationMs - feedback.predicted.durationMs);
    expect(feedback.variance.durationRatioMilli, greaterThan(0));

    final json = feedback.toJson();
    expect(json['predicted'], isA<Map<String, dynamic>>());
    expect(json['observed'], isA<Map<String, dynamic>>());
    expect(json['variance'], isA<Map<String, dynamic>>());
  });
}
