import 'dart:async';
import 'dart:convert';

import '../models/worker_model_catalog.dart';
import '../models/worker_model_runtime_candidate.dart';
import 'device_snapshot.dart';
import 'gemma4_e4b_runtime_benchmark_fixture.dart';
import 'worker_process_memory_telemetry.dart';

/// True when a Gemma4 E4B live benchmark build flag is active (not production).
abstract final class Gemma4E4bBenchmarkMode {
  static const concurrency = 1;

  static bool get active {
    if (const bool.fromEnvironment('WORKER_GEMMA4_BENCHMARK', defaultValue: false)) {
      return true;
    }
    return WorkerModelRuntimeCandidateRegistry.benchmarkOverrideFromEnvironment() !=
        null;
  }

  /// LiteRT resident KV/context size: 2048 for benchmark, 4096 for production.
  static int get residentMaxTokens => active
      ? WorkerModelCatalog.benchmarkContextTokens
      : WorkerModelCatalog.runtimeMaxTokens;
}

/// Controlled benchmark profile shared by Candidate A and Candidate G.
class Gemma4E4bGpuBenchmarkConfig {
  const Gemma4E4bGpuBenchmarkConfig({
    this.contextTokens = Gemma4E4bRuntimeBenchmarkFixture.benchmarkContextTokens,
    this.maxOutputTokens =
        Gemma4E4bRuntimeBenchmarkFixture.benchmarkMaxOutputTokens,
    this.concurrency = 1,
    this.warmRunCount = 3,
    this.peakSampleIntervalMs = 350,
  });

  final int contextTokens;
  final int maxOutputTokens;
  final int concurrency;
  final int warmRunCount;
  final int peakSampleIntervalMs;

  Map<String, Object?> toJson() => {
        'contextTokens': contextTokens,
        'maxOutputTokens': maxOutputTokens,
        'concurrency': concurrency,
        'warmRunCount': warmRunCount,
        'peakSampleIntervalMs': peakSampleIntervalMs,
        'systemInstruction': Gemma4E4bRuntimeBenchmarkFixture.systemInstruction,
        'userPromptLength': Gemma4E4bRuntimeBenchmarkFixture.userPrompt.length,
      };
}

class Gemma4E4bGpuBenchmarkRunMetrics {
  const Gemma4E4bGpuBenchmarkRunMetrics({
    this.artifactSizeBytes,
    this.modelLoadMs,
    this.pssBeforeLoadKb,
    this.pssAfterLoadKb,
    this.loadPssDeltaKb,
    this.peakInferencePssKb,
    this.minimumAvailableDeviceRamMb,
    this.pssAfterSessionCloseKb,
    this.runDurationsMs = const [],
    this.timeToFirstTokenMs,
    this.decodeTokensPerSec,
    this.inputTokenCount,
    this.outputTokenCount,
    this.outputValid,
    this.modelLoadCount,
    this.sessionsOpened,
    this.sessionsClosed,
    this.sessionLeak,
    this.oomOrLmk,
    this.gpuMemory = 'NOT_AVAILABLE',
  });

  final int? artifactSizeBytes;
  final int? modelLoadMs;
  final int? pssBeforeLoadKb;
  final int? pssAfterLoadKb;
  final int? loadPssDeltaKb;
  final int? peakInferencePssKb;
  final int? minimumAvailableDeviceRamMb;
  final int? pssAfterSessionCloseKb;
  final List<int> runDurationsMs;
  final int? timeToFirstTokenMs;
  final double? decodeTokensPerSec;
  final int? inputTokenCount;
  final int? outputTokenCount;
  final bool? outputValid;
  final int? modelLoadCount;
  final int? sessionsOpened;
  final int? sessionsClosed;
  final bool? sessionLeak;
  final String? oomOrLmk;
  final String gpuMemory;

  int? get headroomLossMb {
    final before = pssBeforeLoadKb;
    final minAvail = minimumAvailableDeviceRamMb;
    if (before == null || minAvail == null) {
      return null;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'artifactSizeBytes': artifactSizeBytes,
        'modelLoadMs': modelLoadMs,
        'pssBeforeLoadKb': pssBeforeLoadKb,
        'pssAfterLoadKb': pssAfterLoadKb,
        'loadPssDeltaKb': loadPssDeltaKb,
        'peakInferencePssKb': peakInferencePssKb,
        'minimumAvailableDeviceRamMb': minimumAvailableDeviceRamMb,
        'pssAfterSessionCloseKb': pssAfterSessionCloseKb,
        'runDurationsMs': runDurationsMs,
        'timeToFirstTokenMs': timeToFirstTokenMs,
        'decodeTokensPerSec': decodeTokensPerSec,
        'inputTokenCount': inputTokenCount,
        'outputTokenCount': outputTokenCount,
        'outputValid': outputValid,
        'modelLoadCount': modelLoadCount,
        'sessionsOpened': sessionsOpened,
        'sessionsClosed': sessionsClosed,
        'sessionLeak': sessionLeak,
        'oomOrLmk': oomOrLmk,
        'gpuMemory': gpuMemory,
      };
}

/// Percent delta: (G - A) / A * 100 when both values present.
double? gemma4BenchmarkPercentDelta(num? a, num? g) {
  if (a == null || g == null || a == 0) {
    return null;
  }
  return ((g - a) / a) * 100.0;
}

Map<String, Object?> gemma4BenchmarkComparisonRow({
  required String metric,
  required Object? candidateA,
  required Object? candidateG,
}) {
  final aNum = candidateA is num ? candidateA : null;
  final gNum = candidateG is num ? candidateG : null;
  return {
    'metric': metric,
    'candidateA': candidateA,
    'candidateG': candidateG,
    'percentDeltaGvsA': gemma4BenchmarkPercentDelta(aNum, gNum),
  };
}

/// Validates benchmark JSON output shape (correctness gate helper).
bool gemma4BenchmarkOutputValid(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, dynamic>) {
      return false;
    }
    final summary = decoded['summary'];
    final keyPoints = decoded['keyPoints'];
    final risk = decoded['riskLevel'];
    if (summary is! String || summary.isEmpty) {
      return false;
    }
    if (keyPoints is! List || keyPoints.isEmpty) {
      return false;
    }
    if (risk is! String ||
        (risk != 'low' && risk != 'medium' && risk != 'high')) {
      return false;
    }
    return true;
  } catch (_) {
    return false;
  }
}

typedef ProcessMemoryReader = Future<ProcessMemorySnapshot> Function();

/// Dev-only peak sampling during inference (bounded interval).
abstract final class Gemma4E4bGpuBenchmarkPeakSampler {
  static Timer? _timer;
  static int? _peakPssKb;
  static int? _peakNativeHeapKb;
  static int? _minAvailableRamMb;

  static Future<void> begin({
    required ProcessMemoryReader readMemory,
    Duration interval = const Duration(milliseconds: 350),
  }) async {
    end();
    _peakPssKb = null;
    _peakNativeHeapKb = null;
    _minAvailableRamMb = null;

    Future<void> sample() async {
      try {
        final snap = await readMemory();
        final pss = snap.processPssKb;
        if (pss != null) {
          _peakPssKb = _peakPssKb == null ? pss : (_peakPssKb! < pss ? pss : _peakPssKb);
        }
        final native = snap.nativeHeapKb;
        if (native != null) {
          _peakNativeHeapKb = _peakNativeHeapKb == null
              ? native
              : (_peakNativeHeapKb! < native ? native : _peakNativeHeapKb);
        }
        final avail = snap.deviceAvailableRamMb;
        if (avail != null) {
          _minAvailableRamMb = _minAvailableRamMb == null
              ? avail
              : (_minAvailableRamMb! > avail ? avail : _minAvailableRamMb);
        }
      } catch (_) {
        // Sampling must not disturb inference.
      }
    }

    await sample();
    _timer = Timer.periodic(interval, (_) => unawaited(sample()));
  }

  static WorkerProcessMemoryPeakObservation end() {
    _timer?.cancel();
    _timer = null;
    final observation = WorkerProcessMemoryPeakObservation(
      peakPssKb: _peakPssKb,
      peakNativeHeapKb: _peakNativeHeapKb,
      minimumAvailableDeviceRamMb: _minAvailableRamMb,
    );
    _peakPssKb = null;
    _peakNativeHeapKb = null;
    _minAvailableRamMb = null;
    return observation;
  }
}

class WorkerProcessMemoryPeakObservation {
  const WorkerProcessMemoryPeakObservation({
    this.peakPssKb,
    this.peakNativeHeapKb,
    this.minimumAvailableDeviceRamMb,
  });

  final int? peakPssKb;
  final int? peakNativeHeapKb;
  final int? minimumAvailableDeviceRamMb;
}

/// Records whether live on-device benchmark was executed (evidence export).
class Gemma4E4bGpuBenchmarkEvidence {
  Gemma4E4bGpuBenchmarkEvidence({
    required this.config,
    this.candidateAMetrics,
    this.candidateGMetrics,
    this.deviceModel,
    this.androidVersion,
    this.deviceTotalRamMb,
    this.thermalState,
    this.batteryPercent,
    this.isCharging,
    this.runOrder,
    this.fourGbClassification = '4GB_NOT_TESTED',
    this.integrationStatus = 'D. BENCHMARK_INCOMPLETE',
    this.selectedCandidateId =
        WorkerModelRuntimeCandidateId.generalLitertLmA,
  });

  final Gemma4E4bGpuBenchmarkConfig config;
  final Gemma4E4bGpuBenchmarkRunMetrics? candidateAMetrics;
  final Gemma4E4bGpuBenchmarkRunMetrics? candidateGMetrics;
  final String? deviceModel;
  final String? androidVersion;
  final int? deviceTotalRamMb;
  final String? thermalState;
  final int? batteryPercent;
  final bool? isCharging;
  final List<String>? runOrder;
  final String fourGbClassification;
  final String integrationStatus;
  final WorkerModelRuntimeCandidateId selectedCandidateId;

  Map<String, Object?> toJson() => {
        'config': config.toJson(),
        'candidateA': candidateAMetrics?.toJson(),
        'candidateG': candidateGMetrics?.toJson(),
        'deviceModel': deviceModel,
        'androidVersion': androidVersion,
        'deviceTotalRamMb': deviceTotalRamMb,
        'thermalState': thermalState,
        'batteryPercent': batteryPercent,
        'isCharging': isCharging,
        'runOrder': runOrder,
        'fourGbClassification': fourGbClassification,
        'integrationStatus': integrationStatus,
        'selectedCandidateId': selectedCandidateId.name,
      };
}

/// Selection helper — does not mutate production catalog.
WorkerModelRuntimeCandidateId gemma4SelectPreferredCandidateAfterBenchmark({
  required Gemma4E4bGpuBenchmarkRunMetrics? a,
  required Gemma4E4bGpuBenchmarkRunMetrics? g,
}) {
  if (a == null || g == null) {
    return WorkerModelRuntimeCandidateId.generalLitertLmA;
  }
  if (g.outputValid != true || g.oomOrLmk != null) {
    return WorkerModelRuntimeCandidateId.generalLitertLmA;
  }
  if (g.modelLoadCount != null && g.modelLoadCount! > 1) {
    return WorkerModelRuntimeCandidateId.generalLitertLmA;
  }
  if (g.sessionLeak == true) {
    return WorkerModelRuntimeCandidateId.generalLitertLmA;
  }

  final aPeak = a.peakInferencePssKb;
  final gPeak = g.peakInferencePssKb;
  if (aPeak != null && gPeak != null && gPeak < aPeak) {
    const threshold = 0.05;
    if ((aPeak - gPeak) / aPeak >= threshold) {
      return WorkerModelRuntimeCandidateId.gpuLitertLmG;
    }
  }

  final aLoadDelta = a.loadPssDeltaKb;
  final gLoadDelta = g.loadPssDeltaKb;
  if (aLoadDelta != null &&
      gLoadDelta != null &&
      gLoadDelta < aLoadDelta &&
      (aLoadDelta - gLoadDelta) / aLoadDelta >= 0.05) {
    return WorkerModelRuntimeCandidateId.gpuLitertLmG;
  }

  return WorkerModelRuntimeCandidateId.generalLitertLmA;
}
