import 'dart:convert';
import 'dart:io';

import 'device_capability_profile.dart';
import 'device_inference_policy_config.dart';
import 'worker_pipeline_log.dart';

enum AdmissionRisk { low, medium, high }

class ModelDescriptor {
  const ModelDescriptor({
    required this.modelId,
    required this.modelName,
    required this.modelFileSizeBytes,
    required this.modelFamily,
    required this.quantization,
    required this.supportsText,
    required this.supportsVision,
    required this.supportsAudio,
    required this.recommendedContextTokens,
    required this.minimumRamMb,
    required this.recommendedRamMb,
    required this.preferredBackend,
    required this.artifactSha256,
    required this.peakEstimatedMemoryMb,
    this.largerThanBaseline = false,
    this.qualityRank = 1,
    this.peakEstimatedMemoryByContextMb = const {},
  });

  final String modelId;
  final String modelName;
  final int modelFileSizeBytes;
  final String modelFamily;
  final String quantization;
  final bool supportsText;
  final bool supportsVision;
  final bool supportsAudio;
  final int recommendedContextTokens;
  final int minimumRamMb;
  final int recommendedRamMb;
  final String preferredBackend;
  final String artifactSha256;
  final int peakEstimatedMemoryMb;
  final bool largerThanBaseline;
  final int qualityRank;
  final Map<int, int> peakEstimatedMemoryByContextMb;

  int peakForContext(int contextTokens) =>
      peakEstimatedMemoryByContextMb[contextTokens] ?? peakEstimatedMemoryMb;
}

class ModelAdmissionResult {
  const ModelAdmissionResult({
    required this.admitted,
    required this.selectedBackend,
    required this.selectedContextTokens,
    required this.riskLevel,
    required this.reasons,
    required this.modelId,
    this.visionEligible = false,
    this.reusedBenchmark = false,
  });

  final bool admitted;
  final String selectedBackend;
  final int selectedContextTokens;
  final AdmissionRisk riskLevel;
  final List<String> reasons;
  final String modelId;
  final bool visionEligible;
  final bool reusedBenchmark;

  String logLine() =>
      '[MODEL ADMISSION] model=$modelId admitted=$admitted '
      'backend=$selectedBackend contextTokens=$selectedContextTokens '
      'riskLevel=${riskLevel.name.toUpperCase()} reasons=$reasons';

  Map<String, Object?> toJson() => {
        'admitted': admitted,
        'selectedBackend': selectedBackend,
        'selectedContextTokens': selectedContextTokens,
        'riskLevel': riskLevel.name,
        'reasons': reasons,
        'modelId': modelId,
        'visionEligible': visionEligible,
        'reusedBenchmark': reusedBenchmark,
      };

  static ModelAdmissionResult fromJson(Map<String, Object?> json) {
    return ModelAdmissionResult(
      admitted: json['admitted'] == true,
      selectedBackend: json['selectedBackend'] as String? ?? 'unknown',
      selectedContextTokens: json['selectedContextTokens'] as int? ?? 0,
      riskLevel: AdmissionRisk.values.byName(json['riskLevel'] as String? ?? 'high'),
      reasons: (json['reasons'] as List<Object?>?)?.cast<String>() ?? const [],
      modelId: json['modelId'] as String? ?? '',
      visionEligible: json['visionEligible'] == true,
      reusedBenchmark: json['reusedBenchmark'] == true,
    );
  }
}

class OomBlockRecord {
  const OomBlockRecord({required this.availableRamMb});

  final int? availableRamMb;

  Map<String, Object?> toJson() => {'availableRamMb': availableRamMb};

  static OomBlockRecord fromJson(Map<String, Object?> json) {
    return OomBlockRecord(availableRamMb: json['availableRamMb'] as int?);
  }
}

abstract class AdmissionCacheStore {
  String? read(String key);
  void write(String key, String value);
}

class MemoryAdmissionCacheStore implements AdmissionCacheStore {
  final Map<String, String> values = {};

  @override
  String? read(String key) => values[key];

  @override
  void write(String key, String value) {
    values[key] = value;
  }
}

class FileAdmissionCacheStore implements AdmissionCacheStore {
  FileAdmissionCacheStore(this.file) {
    if (!file.existsSync()) {
      return;
    }
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map) {
        decoded.forEach((key, value) {
          _values['$key'] = '$value';
        });
      }
    } catch (_) {
      _values.clear();
    }
  }

  final File file;
  final Map<String, String> _values = {};

  @override
  String? read(String key) => _values[key];

  @override
  void write(String key, String value) {
    _values[key] = value;
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(_values));
    } catch (_) {}
  }
}

class AdmissionResultCache {
  AdmissionResultCache({AdmissionCacheStore? store})
      : _store = store ?? MemoryAdmissionCacheStore();

  final AdmissionCacheStore _store;

  static String cacheKey({
    required String fingerprint,
    required String modelSha256,
    required String runtimeVersion,
    required String appVersion,
    required int contextTokens,
    required int? availableRamMb,
    required int? totalRamMb,
    required double maxFreeResourceFraction,
  }) =>
      '$fingerprint|$modelSha256|$runtimeVersion|$appVersion|$contextTokens|'
      '${availableRamMb ?? 'null'}|${totalRamMb ?? 'null'}|$maxFreeResourceFraction';

  static String oomKey({
    required String fingerprint,
    required String modelSha256,
  }) =>
      'oom|$fingerprint|$modelSha256';

  ModelAdmissionResult? read({
    required String fingerprint,
    required String modelSha256,
    required String runtimeVersion,
    required String appVersion,
    required int contextTokens,
    required int? availableRamMb,
    required int? totalRamMb,
    required double maxFreeResourceFraction,
  }) {
    final raw = _store.read(
      cacheKey(
        fingerprint: fingerprint,
        modelSha256: modelSha256,
        runtimeVersion: runtimeVersion,
        appVersion: appVersion,
        contextTokens: contextTokens,
        availableRamMb: availableRamMb,
        totalRamMb: totalRamMb,
        maxFreeResourceFraction: maxFreeResourceFraction,
      ),
    );
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return null;
    }
    return ModelAdmissionResult.fromJson(decoded.cast<String, Object?>());
  }

  void write({
    required String fingerprint,
    required String modelSha256,
    required String runtimeVersion,
    required String appVersion,
    required int contextTokens,
    required int? availableRamMb,
    required int? totalRamMb,
    required double maxFreeResourceFraction,
    required ModelAdmissionResult result,
  }) {
    _store.write(
      cacheKey(
        fingerprint: fingerprint,
        modelSha256: modelSha256,
        runtimeVersion: runtimeVersion,
        appVersion: appVersion,
        contextTokens: contextTokens,
        availableRamMb: availableRamMb,
        totalRamMb: totalRamMb,
        maxFreeResourceFraction: maxFreeResourceFraction,
      ),
      jsonEncode(result.toJson()),
    );
  }

  OomBlockRecord? readOom({
    required String fingerprint,
    required String modelSha256,
  }) {
    final raw = _store.read(oomKey(fingerprint: fingerprint, modelSha256: modelSha256));
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return null;
    }
    return OomBlockRecord.fromJson(decoded.cast<String, Object?>());
  }

  void writeOom({
    required String fingerprint,
    required String modelSha256,
    required int? availableRamMb,
  }) {
    _store.write(
      oomKey(fingerprint: fingerprint, modelSha256: modelSha256),
      jsonEncode(OomBlockRecord(availableRamMb: availableRamMb).toJson()),
    );
  }
}

class ModelAdmissionPolicy {
  const ModelAdmissionPolicy({
    this.config = const DeviceInferencePolicyConfig(),
    this.cache,
  });

  final DeviceInferencePolicyConfig config;
  final AdmissionResultCache? cache;

  ModelAdmissionResult evaluate({
    required DeviceCapabilityProfile device,
    required ModelDescriptor model,
    int? contextTokens,
    DeviceBenchmarkMetrics? benchmark,
    bool visionRequested = false,
  }) {
    final requested = contextTokens ?? model.recommendedContextTokens;
    final observed = benchmark ?? _benchmarkForContext(device, model, requested);
    final reasons = <String>[];
    final oom = cache?.readOom(
      fingerprint: device.fingerprint,
      modelSha256: model.artifactSha256,
    );
    final ramImproved = oom != null &&
        _meaningfullyMoreRam(oom.availableRamMb, device.availableRamMb);
    if (oom != null && !ramImproved) {
      reasons.add('oom_blocked_no_meaningful_change');
      return _finish(
        device: device,
        model: model,
        contextTokens: requested,
        admitted: false,
        risk: AdmissionRisk.high,
        reasons: reasons,
        visionEligible: false,
      );
    }

    final cached = ramImproved
        ? null
        : cache?.read(
            fingerprint: device.fingerprint,
            modelSha256: model.artifactSha256,
            runtimeVersion: config.runtimeVersion,
            appVersion: config.appVersion,
            contextTokens: requested,
            availableRamMb: device.availableRamMb,
            totalRamMb: device.totalRamMb,
            maxFreeResourceFraction: config.memory.maxFreeResourceFraction,
          );
    if (cached != null) {
      final reused = ModelAdmissionResult(
        admitted: cached.admitted,
        selectedBackend: cached.selectedBackend,
        selectedContextTokens: cached.selectedContextTokens,
        riskLevel: cached.riskLevel,
        reasons: [...cached.reasons, 'benchmark_reused'],
        modelId: cached.modelId,
        visionEligible: cached.visionEligible,
        reusedBenchmark: true,
      );
      _trace(
        model: model,
        contextTokens: requested,
        device: device,
        budget: config.memory.safeBudgetMb(
          availableRamMb: device.availableRamMb,
          totalRamMb: device.totalRamMb,
        ),
        observedPeakRssMb: observed?.peakRssMb,
        peakForContextMb: model.peakForContext(requested),
        peak: null,
        benchmarkStatus: 'cache_hit',
        comparison: 'cached',
        admitted: reused.admitted,
        reasons: reused.reasons,
      );
      WorkerPipelineLog.info(WorkerPipelineLog.model, reused.logLine());
      return reused;
    }

    final budget = config.memory.safeBudgetMb(
      availableRamMb: device.availableRamMb,
      totalRamMb: device.totalRamMb,
    );
    final peak = observed?.peakRssMb ?? model.peakForContext(requested);
    if (budget == null) {
      reasons.add('memory_unknown');
    } else if (peak >= budget) {
      reasons.add('memory_budget_exceeded');
    }
    final available = device.availableRamMb;
    if (available != null && available < model.minimumRamMb) {
      reasons.add('below_minimum_ram');
    }
    if (model.largerThanBaseline && device.tier == DeviceTier.low) {
      reasons.add('larger_model_low_tier');
    }
    if (requested == config.wideContextTokens &&
        (observed == null || !observed.succeededForContext(config.wideContextTokens))) {
      reasons.add('context_4096_without_benchmark');
    } else if (requested > 3072 &&
        (observed == null || !observed.succeededForContext(requested))) {
      reasons.add('larger_context_without_benchmark');
    }
    if (model.largerThanBaseline &&
        requested > config.baselineContextTokens &&
        (observed == null || !observed.succeededForContext(requested))) {
      reasons.add('larger_model_context_unbenchmarked');
    }
    _hardBenchmarkFailures(observed, reasons);
    if (observed?.peakRssMb != null && budget != null && observed!.peakRssMb! > budget) {
      if (!reasons.contains('peak_rss_exceeds_budget')) {
        reasons.add('peak_rss_exceeds_budget');
      }
    }

    final withinPolicyContext = !model.largerThanBaseline && requested <= 3072;
    final hardReject = reasons.any(_isHardReject);
    final memoryReject = reasons.contains('memory_budget_exceeded') ||
        reasons.contains('below_minimum_ram') ||
        reasons.contains('peak_rss_exceeds_budget');
    var admitted = !hardReject && !memoryReject;
    if (admitted && budget == null && !withinPolicyContext) {
      admitted = false;
    }
    if (admitted && observed == null && !withinPolicyContext) {
      admitted = false;
      reasons.add('benchmark_required');
    }
    if (admitted && observed == null && withinPolicyContext && budget != null) {
      reasons.add('baseline_context_pending_benchmark');
    }
    if (admitted && observed == null && withinPolicyContext && budget == null) {
      reasons.add('profile_incomplete_baseline_only');
    }

    final ratio = budget == null || budget <= 0 ? 1.0 : peak / budget;
    final risk = !admitted
        ? AdmissionRisk.high
        : ratio >= config.memory.highRiskRatio
            ? AdmissionRisk.high
            : ratio >= config.memory.mediumRiskRatio
                ? AdmissionRisk.medium
                : AdmissionRisk.low;
    final headroom = budget == null ? null : budget - peak;
    final visionEligible = admitted &&
        model.supportsVision &&
        !config.tiers.forHardware(device.hardwareTier).multimodalRestricted &&
        device.tier != DeviceTier.unsupported &&
        headroom != null &&
        headroom >= config.visionHeadroomMb &&
        (visionRequested || true);
    if (visionRequested && !visionEligible) {
      reasons.add('vision_insufficient_headroom');
    }
    if (admitted && reasons.isEmpty) {
      reasons.add('admitted');
    }
    _trace(
      model: model,
      contextTokens: requested,
      device: device,
      budget: budget,
      observedPeakRssMb: observed?.peakRssMb,
      peakForContextMb: model.peakForContext(requested),
      peak: peak,
      benchmarkStatus: observed == null ? 'none' : 'matched',
      comparison: budget == null ? 'budget == null' : 'peak >= budget',
      admitted: admitted,
      reasons: reasons,
    );
    WorkerPipelineLog.info(
      WorkerPipelineLog.model,
      '[MODEL ADMISSION MEMORY] contextTokens=$requested '
      'availableRamMb=${device.availableRamMb ?? 'unknown'} '
      'availableRamRatio=${config.memory.maxFreeResourceFraction} '
      'memoryBudgetMb=${budget ?? 'unknown'} '
      'peak=$peak '
      'admitted=$admitted '
      'reason=${reasons.join(',')}',
    );
    return _finish(
      device: device,
      model: model,
      contextTokens: requested,
      admitted: admitted,
      risk: risk,
      reasons: reasons,
      visionEligible: visionEligible && !visionRequested ? visionEligible : visionEligible,
      benchmarkFailedHard: observed != null &&
          (observed.nativeOom || observed.lowMemoryOrLmk),
    );
  }

  void _trace({
    required ModelDescriptor model,
    required int contextTokens,
    required DeviceCapabilityProfile device,
    required int? budget,
    required int? observedPeakRssMb,
    required int peakForContextMb,
    required int? peak,
    required String benchmarkStatus,
    required String comparison,
    required bool admitted,
    required List<String> reasons,
  }) {
    WorkerPipelineLog.info(
      WorkerPipelineLog.model,
      '[MODEL ADMISSION TRACE] '
      'model=${model.modelId} '
      'contextTokens=$contextTokens '
      'totalRamMb=${device.totalRamMb ?? 'unknown'} '
      'availableRamMb=${device.availableRamMb ?? 'unknown'} '
      'availableRamRatio=${config.memory.maxFreeResourceFraction} '
      'memoryBudgetMb=${budget ?? 'unknown'} '
      'observedPeakRssMb=${observedPeakRssMb ?? 'null'} '
      'peakForContext=$peakForContextMb '
      'peak=${peak ?? 'not_recomputed'} '
      'benchmarkStatus=$benchmarkStatus '
      'residentModelLoaded=not_consulted '
      'comparison=$comparison '
      'admitted=$admitted '
      'reasons=$reasons',
    );
  }

  bool _meaningfullyMoreRam(int? blockedAt, int? current) {
    if (blockedAt == null || current == null) {
      return false;
    }
    return current >= blockedAt + config.oomRamImprovementMb;
  }

  DeviceBenchmarkMetrics? _benchmarkForContext(
    DeviceCapabilityProfile device,
    ModelDescriptor model,
    int contextTokens,
  ) {
    final benchmark = device.benchmark;
    if (benchmark == null) {
      return null;
    }
    if (benchmark.modelSha256 != model.artifactSha256) {
      return null;
    }
    if (benchmark.contextTokens != null && benchmark.contextTokens != contextTokens) {
      return null;
    }
    return benchmark;
  }

  void _hardBenchmarkFailures(DeviceBenchmarkMetrics? benchmark, List<String> reasons) {
    if (benchmark == null) {
      return;
    }
    if (benchmark.engineLoadFailed) {
      reasons.add('engine_load_failure');
    }
    if (benchmark.lowMemoryOrLmk) {
      reasons.add('low_memory_lmk');
    }
    if (benchmark.nativeOom) {
      reasons.add('native_oom');
    }
    if (benchmark.repeatedInferenceCrash) {
      reasons.add('repeated_inference_crash');
    }
    if (benchmark.thermalCritical) {
      reasons.add('thermal_critical');
    }
    if (benchmark.peakRssMb != null) {
      // Compared with the budget by the caller when the budget exists.
    }
  }

  bool _isHardReject(String reason) {
    return reason == 'engine_load_failure' ||
        reason == 'low_memory_lmk' ||
        reason == 'native_oom' ||
        reason == 'repeated_inference_crash' ||
        reason == 'thermal_critical' ||
        reason == 'oom_blocked_no_meaningful_change' ||
        reason == 'context_4096_without_benchmark' ||
        reason == 'larger_context_without_benchmark' ||
        reason == 'larger_model_low_tier' ||
        reason == 'larger_model_context_unbenchmarked';
  }

  ModelAdmissionResult _finish({
    required DeviceCapabilityProfile device,
    required ModelDescriptor model,
    required int contextTokens,
    required bool admitted,
    required AdmissionRisk risk,
    required List<String> reasons,
    required bool visionEligible,
    bool benchmarkFailedHard = false,
  }) {
    final result = ModelAdmissionResult(
      admitted: admitted,
      selectedBackend: admitted ? model.preferredBackend : 'none',
      selectedContextTokens: contextTokens,
      riskLevel: risk,
      reasons: reasons,
      modelId: model.modelId,
      visionEligible: admitted && visionEligible,
    );
    if (benchmarkFailedHard) {
      cache?.writeOom(
        fingerprint: device.fingerprint,
        modelSha256: model.artifactSha256,
        availableRamMb: device.availableRamMb,
      );
    }
    cache?.write(
      fingerprint: device.fingerprint,
      modelSha256: model.artifactSha256,
      runtimeVersion: config.runtimeVersion,
      appVersion: config.appVersion,
      contextTokens: contextTokens,
      availableRamMb: device.availableRamMb,
      totalRamMb: device.totalRamMb,
      maxFreeResourceFraction: config.memory.maxFreeResourceFraction,
      result: result,
    );
    WorkerPipelineLog.info(WorkerPipelineLog.model, result.logLine());
    return result;
  }
}
