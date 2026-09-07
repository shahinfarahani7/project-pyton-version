/// Baseline resource envelopes aligned with dsl/catalog/resource-envelopes/*.yaml.
class ResourceEnvelopeBaseline {
  const ResourceEnvelopeBaseline({
    required this.runtimeClass,
    required this.cpuUnits,
    required this.peakMemoryBytes,
    required this.durationMs,
  });

  final String runtimeClass;
  final int cpuUnits;
  final int peakMemoryBytes;
  final int durationMs;
}

abstract final class ResourceEnvelopeCatalog {
  static const _envelopes = <String, ResourceEnvelopeBaseline>{
    'text.summarize': ResourceEnvelopeBaseline(
      runtimeClass: 'mediapipe_llm',
      cpuUnits: 40,
      peakMemoryBytes: 1610612736,
      durationMs: 180000,
    ),
    'text.classify': ResourceEnvelopeBaseline(
      runtimeClass: 'mediapipe_llm',
      cpuUnits: 40,
      peakMemoryBytes: 1610612736,
      durationMs: 120000,
    ),
    'document.extract': ResourceEnvelopeBaseline(
      runtimeClass: 'mediapipe_llm',
      cpuUnits: 40,
      peakMemoryBytes: 1610612736,
      durationMs: 180000,
    ),
    'document.summarize': ResourceEnvelopeBaseline(
      runtimeClass: 'mediapipe_llm',
      cpuUnits: 40,
      peakMemoryBytes: 1610612736,
      durationMs: 240000,
    ),
    'document.ocr': ResourceEnvelopeBaseline(
      runtimeClass: 'paddle_ocr',
      cpuUnits: 25,
      peakMemoryBytes: 536870912,
      durationMs: 120000,
    ),
    'vision.analyze': ResourceEnvelopeBaseline(
      runtimeClass: 'vlm_runtime',
      cpuUnits: 35,
      peakMemoryBytes: 1073741824,
      durationMs: 150000,
    ),
    'image.remove_background': ResourceEnvelopeBaseline(
      runtimeClass: 'segmentation_runtime',
      cpuUnits: 25,
      peakMemoryBytes: 805306368,
      durationMs: 90000,
    ),
  };

  static ResourceEnvelopeBaseline forTaskType(String taskType) {
    return _envelopes[taskType] ??
        const ResourceEnvelopeBaseline(
          runtimeClass: 'system',
          cpuUnits: 25,
          peakMemoryBytes: 536870912,
          durationMs: 90000,
        );
  }

  static ResourceEnvelopeBaseline scaledForInput({
    required String taskType,
    required int inputBytes,
    int calibrationFactorBps = 10000,
  }) {
    final baseline = forTaskType(taskType);
    final loadFactor = _loadFactor(
      runtimeClass: baseline.runtimeClass,
      inputBytes: inputBytes,
    );
    final scaledDuration = _applyBps(baseline.durationMs * loadFactor, calibrationFactorBps);
    final scaledMemory =
        baseline.peakMemoryBytes + (loadFactor - 1) * (baseline.peakMemoryBytes ~/ 4);
    final scaledCpu = baseline.cpuUnits + (loadFactor - 1) * (baseline.cpuUnits ~/ 5);
    return ResourceEnvelopeBaseline(
      runtimeClass: baseline.runtimeClass,
      cpuUnits: scaledCpu,
      peakMemoryBytes: scaledMemory,
      durationMs: scaledDuration,
    );
  }

  static int _loadFactor({required String runtimeClass, required int inputBytes}) {
    final byteFactor = ((inputBytes <= 0 ? 1 : inputBytes) + (512 * 1024) - 1) ~/ (512 * 1024);
    if (runtimeClass == 'mediapipe_llm' || runtimeClass == 'vlm_runtime') {
      return byteFactor.clamp(1, 8);
    }
    if (runtimeClass == 'paddle_ocr') {
      return byteFactor.clamp(1, 16);
    }
    return 1;
  }

  static int _applyBps(int value, int bps) => (value * bps ~/ 10000).clamp(1, 1 << 30);
}
