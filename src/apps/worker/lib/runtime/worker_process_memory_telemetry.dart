/// Process/device memory readings for model lifecycle diagnostics.
class ProcessMemorySnapshot {
  const ProcessMemorySnapshot({
    this.deviceTotalRamMb,
    this.deviceAvailableRamMb,
    this.lowMemory,
    this.processPssKb,
    this.processPrivateDirtyKb,
    this.javaHeapKb,
    this.nativeHeapKb,
  });

  final int? deviceTotalRamMb;
  final int? deviceAvailableRamMb;
  final bool? lowMemory;
  final int? processPssKb;
  final int? processPrivateDirtyKb;
  final int? javaHeapKb;
  final int? nativeHeapKb;
}

/// Records memory at model lifecycle phases (production-safe, low frequency).
abstract final class WorkerProcessMemoryTelemetry {
  static final _phases = <String, ProcessMemorySnapshot>{};

  static void recordPhase(String phase, ProcessMemorySnapshot snapshot) {
    _phases[phase] = snapshot;
  }

  static Map<String, ProcessMemorySnapshot> get phases => Map.unmodifiable(_phases);

  static void clear() => _phases.clear();
}

/// Dev/evidence benchmark row (not a production task type).
class WorkerModelMemoryBenchmarkRow {
  const WorkerModelMemoryBenchmarkRow({
    required this.candidateId,
    required this.artifactFileName,
    required this.sourceFormat,
    required this.runtimeFormat,
    this.artifactSizeBytes,
    this.availableRamBeforeLoadMb,
    this.loadRamDeltaPssKb,
    this.inferencePeakPssKb,
    this.ramAfterSessionClosePssKb,
    this.startupMs,
    this.inferenceMs,
    this.outputValid,
    this.stableSequentialTasks,
  });

  final String candidateId;
  final String artifactFileName;
  final String sourceFormat;
  final String runtimeFormat;
  final int? artifactSizeBytes;
  final int? availableRamBeforeLoadMb;
  final int? loadRamDeltaPssKb;
  final int? inferencePeakPssKb;
  final int? ramAfterSessionClosePssKb;
  final int? startupMs;
  final int? inferenceMs;
  final bool? outputValid;
  final bool? stableSequentialTasks;

  Map<String, Object?> toJson() => {
        'candidateId': candidateId,
        'artifactFileName': artifactFileName,
        'sourceFormat': sourceFormat,
        'runtimeFormat': runtimeFormat,
        'artifactSizeBytes': artifactSizeBytes,
        'availableRamBeforeLoadMb': availableRamBeforeLoadMb,
        'loadRamDeltaPssKb': loadRamDeltaPssKb,
        'inferencePeakPssKb': inferencePeakPssKb,
        'ramAfterSessionClosePssKb': ramAfterSessionClosePssKb,
        'startupMs': startupMs,
        'inferenceMs': inferenceMs,
        'outputValid': outputValid,
        'stableSequentialTasks': stableSequentialTasks,
      };
}
