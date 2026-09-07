import '../runtime/device_snapshot.dart';
import 'resource_envelope_catalog.dart';
import 'worker_task_metrics.dart';

class PredictedResourceUsage {
  const PredictedResourceUsage({
    required this.cpuUnits,
    required this.peakMemoryBytes,
    required this.durationMs,
    required this.energyClass,
    this.runtimeClass,
    this.calibrationFactorBps,
  });

  final int cpuUnits;
  final int peakMemoryBytes;
  final int durationMs;
  final String energyClass;
  final String? runtimeClass;
  final int? calibrationFactorBps;

  Map<String, dynamic> toJson() => {
        'cpuUnits': cpuUnits,
        'peakMemoryBytes': peakMemoryBytes,
        'durationMs': durationMs,
        'energyClass': energyClass,
        if (runtimeClass != null) 'runtimeClass': runtimeClass,
        if (calibrationFactorBps != null) 'calibrationFactorBps': calibrationFactorBps,
      };
}

class ObservedResourceUsage {
  const ObservedResourceUsage({
    required this.cpuAverageBps,
    required this.peakMemoryBytes,
    required this.durationMs,
    required this.thermalDeltaBps,
    this.throughputPerSec,
    this.throughputUnit,
  });

  final int cpuAverageBps;
  final int peakMemoryBytes;
  final int durationMs;
  final int thermalDeltaBps;
  final double? throughputPerSec;
  final String? throughputUnit;

  Map<String, dynamic> toJson() => {
        'cpuAverageBps': cpuAverageBps,
        'peakMemoryBytes': peakMemoryBytes,
        'durationMs': durationMs,
        'thermalDeltaBps': thermalDeltaBps,
        if (throughputPerSec != null) 'throughputPerSec': throughputPerSec,
        if (throughputUnit != null) 'throughputUnit': throughputUnit,
      };
}

class ExecutionCostVariance {
  const ExecutionCostVariance({
    required this.durationMs,
    required this.peakMemoryBytes,
    required this.durationRatioMilli,
  });

  final int durationMs;
  final int peakMemoryBytes;
  final int durationRatioMilli;

  Map<String, dynamic> toJson() => {
        'durationMs': durationMs,
        'peakMemoryBytes': peakMemoryBytes,
        'durationRatioMilli': durationRatioMilli,
      };
}

class ExecutionCostFeedback {
  const ExecutionCostFeedback({
    required this.predicted,
    required this.observed,
    required this.variance,
  });

  final PredictedResourceUsage predicted;
  final ObservedResourceUsage observed;
  final ExecutionCostVariance variance;

  Map<String, dynamic> toJson() => {
        'predicted': predicted.toJson(),
        'observed': observed.toJson(),
        'variance': variance.toJson(),
      };
}

class ExecutionCostFeedbackBuilder {
  ExecutionCostFeedbackBuilder({
    required this.taskType,
    required this.inputBytes,
    required this.startSnapshot,
    this.calibrationFactorBps = 10000,
    this.cpuAverageBps = 0,
  });

  final String taskType;
  final int inputBytes;
  final DeviceSnapshot startSnapshot;
  final int calibrationFactorBps;
  final int cpuAverageBps;

  ExecutionCostFeedback build({
    required WorkerTaskMetrics metrics,
    required DeviceSnapshot endSnapshot,
  }) {
    final envelope = ResourceEnvelopeCatalog.scaledForInput(
      taskType: taskType,
      inputBytes: inputBytes,
      calibrationFactorBps: calibrationFactorBps,
    );
    final predicted = PredictedResourceUsage(
      cpuUnits: envelope.cpuUnits,
      peakMemoryBytes: envelope.peakMemoryBytes,
      durationMs: envelope.durationMs,
      energyClass: _energyClass(envelope.cpuUnits, envelope.durationMs),
      runtimeClass: envelope.runtimeClass,
      calibrationFactorBps: calibrationFactorBps,
    );

    final durationMs = metrics.totalMs;
    final peakMemoryBytes = (metrics.peakMemoryMb ?? 0) * 1024 * 1024;
    final throughput = _throughput(metrics);
    final observed = ObservedResourceUsage(
      cpuAverageBps: cpuAverageBps,
      peakMemoryBytes: peakMemoryBytes,
      durationMs: durationMs,
      thermalDeltaBps: _thermalDeltaBps(startSnapshot.thermalState, endSnapshot.thermalState),
      throughputPerSec: throughput?.value,
      throughputUnit: throughput?.unit,
    );

    final variance = ExecutionCostVariance(
      durationMs: observed.durationMs - predicted.durationMs,
      peakMemoryBytes: observed.peakMemoryBytes - predicted.peakMemoryBytes,
      durationRatioMilli: predicted.durationMs <= 0
          ? 0
          : (observed.durationMs * 1000 ~/ predicted.durationMs),
    );

    return ExecutionCostFeedback(
      predicted: predicted,
      observed: observed,
      variance: variance,
    );
  }

  static String _energyClass(int cpuUnits, int durationMs) {
    final load = cpuUnits * durationMs;
    if (load >= 8000000) return 'high';
    if (load >= 3000000) return 'medium';
    return 'low';
  }

  static int _thermalDeltaBps(ThermalState start, ThermalState end) {
    int ordinal(ThermalState state) => switch (state) {
          ThermalState.normal => 0,
          ThermalState.warm => 2500,
          ThermalState.throttled => 5000,
          ThermalState.critical => 7500,
        };
    return (ordinal(end) - ordinal(start)).clamp(0, 10000);
  }

  static _Throughput? _throughput(WorkerTaskMetrics metrics) {
    if (metrics.llmMs > 0) {
      final tokens = (metrics.inputBytes ?? 0) ~/ 4;
      if (tokens <= 0) return null;
      return _Throughput(tokens / (metrics.llmMs / 1000), 'tokens');
    }
    if (metrics.ocrMs > 0) {
      final pages = ((metrics.inputBytes ?? 0) / (256 * 1024)).ceil().clamp(1, 64);
      return _Throughput(pages / (metrics.ocrMs / 1000), 'pages');
    }
    return null;
  }
}

class _Throughput {
  const _Throughput(this.value, this.unit);

  final double value;
  final String unit;
}
