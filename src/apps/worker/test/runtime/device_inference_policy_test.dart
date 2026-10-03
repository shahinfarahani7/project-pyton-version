import 'dart:io';

import 'package:edgemint_worker/runtime/device_capability_profile.dart';
import 'package:edgemint_worker/runtime/device_inference_policy_config.dart';
import 'package:edgemint_worker/runtime/device_snapshot.dart';
import 'package:edgemint_worker/runtime/gemma_generation_output_limit.dart';
import 'package:edgemint_worker/runtime/long_form_execution_budget.dart';
import 'package:edgemint_worker/runtime/model_admission_policy.dart';
import 'package:edgemint_worker/runtime/model_selection_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const gemma = InferenceModelCatalog.gemma4E4bGpu;
  const larger = InferenceModelCatalog.futureLarger;
  const policy = ModelAdmissionPolicy();
  const selection = ModelSelectionPolicy();

  DeviceCapabilityProfile measured({
    int? totalRamMb = 8192,
    int? availableRamMb = 4096,
    double? decode,
    double? sustained,
    int? peakRssMb,
    int? contextTokens = 2048,
    bool gpu = true,
    double? headroom = 0.5,
    ThermalState thermal = ThermalState.normal,
    bool engineLoadFailed = false,
    bool nativeOom = false,
    bool lowMemory = false,
    String model = 'TEST',
    List<int> cpuPartIds = const [],
    String? modelSha256 =
        '4912bb5a9c30993c51a7711f763212077458529312175df0573a78323a2bb7ff',
  }) {
    return DeviceCapabilityProfile(
      manufacturer: 'Samsung',
      model: model,
      totalRamMb: totalRamMb,
      availableRamMb: availableRamMb,
      lowMemoryThresholdMb: 800,
      cpuArchitecture: 'arm64-v8a',
      cpuPartIds: cpuPartIds,
      gpuAvailable: gpu,
      gpuBackend: gpu ? 'OpenCL' : null,
      thermalState: thermal,
      thermalHeadroom: headroom,
      benchmark: decode == null && !engineLoadFailed && !nativeOom && !lowMemory
          ? null
          : DeviceBenchmarkMetrics(
              engineLoadMs: engineLoadFailed ? null : 30000,
              decodeChunksPerSecond: decode,
              sustainedDecodeChunksPerSecond: sustained,
              peakRssMb: peakRssMb,
              contextTokens: contextTokens,
              modelSha256: modelSha256,
              engineLoadFailed: engineLoadFailed,
              nativeOom: nativeOom,
              lowMemoryOrLmk: lowMemory,
            ),
    );
  }

  test('lookup uses only total RAM and CPU class', () {
    final sixC2 = DeviceTierLookup.policy(totalRamMb: 6 * 1024, cpuClass: CpuClass.c2);
    expect(DeviceTierLookup.resolve(totalRamMb: 6 * 1024, cpuClass: CpuClass.c2), HardwareTier.t2);
    expect(sixC2.contextTokens, 2048);
    expect(sixC2.perStageOutput, 256);
    expect(DeviceTierLookup.resolve(totalRamMb: 6 * 1024, cpuClass: CpuClass.c0), HardwareTier.t1);
    expect(DeviceTierLookup.resolve(totalRamMb: 12 * 1024, cpuClass: CpuClass.c1), HardwareTier.t2);
    expect(DeviceTierLookup.resolve(totalRamMb: 16 * 1024, cpuClass: CpuClass.c4), HardwareTier.t5);
    expect(DeviceTierLookup.resolve(totalRamMb: 16 * 1024, cpuClass: CpuClass.unknown), HardwareTier.t2);
    final pressured = DeviceTierLookup.resolve(totalRamMb: 12 * 1024, cpuClass: CpuClass.c4);
    expect(pressured, HardwareTier.t4);
  });

  test('tight free RAM keeps Gemma by lowering context instead of dropping the model', () {
    final device = measured(
      totalRamMb: 6144,
      availableRamMb: 1600,
      cpuPartIds: const [0xD41],
    );
    final chosen = selection.select(
      device: device,
      request: const ModelSelectionRequest(taskType: 'text.direct'),
    );
    expect(chosen.admitted, isTrue);
    expect(chosen.selectedModelId, gemma.modelId);
    expect(chosen.selectedContextTokens, 1536);
    expect(chosen.reason, 'context_downgraded_to_1536');
  });

  test('safe memory budget keeps a system reserve', () {
    const memory = MemorySafetyConfig();
    expect(memory.maxFreeResourceFraction, 0.75);
    expect(
      memory.safeBudgetMb(availableRamMb: 3072, totalRamMb: 6144),
      2304,
    );
    expect(
      memory.safeBudgetMb(availableRamMb: 2932, totalRamMb: 7398),
      2199,
    );
    final device = measured(
      totalRamMb: 7398,
      availableRamMb: 2932,
      cpuPartIds: const [0xD41],
    );
    final chosen = selection.select(
      device: device,
      request: const ModelSelectionRequest(taskType: 'text.direct'),
    );
    expect(chosen.memoryBudgetMb, 2199);
    const ladder = [2048, 1536, 1024];
    final fitting = ladder.firstWhere((context) => gemma.peakForContext(context) < 2199);
    expect(chosen.admitted, isTrue);
    expect(chosen.selectedContextTokens, fitting);
    expect(memory.safeBudgetMb(availableRamMb: null, totalRamMb: 6144), isNull);
  });

  test('7398/2960 admits Gemma at 2048 because peakForContext is below budget 2220', () {
    const memory = MemorySafetyConfig();
    final budget = memory.safeBudgetMb(availableRamMb: 2960, totalRamMb: 7398);
    expect(budget, 2220);
    expect((2960 * memory.maxFreeResourceFraction).floor(), 2220);
    expect(7398 - memory.systemReserveMb, 5862);
    final device = measured(
      totalRamMb: 7398,
      availableRamMb: 2960,
      cpuPartIds: const [0xD41],
    );
    expect(device.cpuClass, CpuClass.c2);
    expect(device.ramTier, RamTier.t2);
    expect(device.hardwareTier, HardwareTier.t2);
    expect(device.benchmark, isNull);
    for (final context in [2048, 1536, 1024]) {
      final result = policy.evaluate(device: device, model: gemma, contextTokens: context);
      final peak = gemma.peakForContext(context);
      expect(result.reasons.contains('memory_budget_exceeded'), peak >= budget!);
      expect(result.admitted, peak < budget);
      expect(result.reusedBenchmark, isFalse);
    }
    final chosen = selection.select(
      device: device,
      request: const ModelSelectionRequest(taskType: 'text.direct'),
    );
    expect(chosen.memoryBudgetMb, 2220);
    expect(chosen.selectedContextTokens, 2048);
    expect(chosen.admitted, isTrue);
    expect(chosen.reason, isNot(contains('memory_budget_exceeded')));
  });

  test('memory_budget_exceeded is recomputed when available RAM or the free fraction changes', () {
    final store = MemoryAdmissionCacheStore();
    const oldConfig = DeviceInferencePolicyConfig(
      memory: MemorySafetyConfig(maxFreeResourceFraction: 0.50),
    );
    final oldAdmission = ModelAdmissionPolicy(
      config: oldConfig,
      cache: AdmissionResultCache(store: store),
    );
    final tight = measured(
      totalRamMb: 7398,
      availableRamMb: 2000,
      cpuPartIds: const [0xD41],
    );
    final tightBudget = oldConfig.memory.safeBudgetMb(
      availableRamMb: 2000,
      totalRamMb: 7398,
    );
    expect(tightBudget, 1000);
    for (final context in [2048, 1536, 1024]) {
      final result = oldAdmission.evaluate(device: tight, model: gemma, contextTokens: context);
      final peak = gemma.peakForContext(context);
      expect(result.reasons.contains('memory_budget_exceeded'), peak >= tightBudget!);
      expect(result.admitted, peak < tightBudget);
    }
    final current = ModelAdmissionPolicy(cache: AdmissionResultCache(store: store));
    final now = measured(
      totalRamMb: 7398,
      availableRamMb: 2960,
      cpuPartIds: const [0xD41],
    );
    expect(now.fingerprint, tight.fingerprint);
    final again = current.evaluate(device: now, model: gemma, contextTokens: 2048);
    expect(again.reusedBenchmark, isFalse);
    expect(again.reasons, isNot(contains('benchmark_reused')));
    expect(again.reasons.contains('memory_budget_exceeded'), gemma.peakForContext(2048) >= 2220);
    expect(again.admitted, isTrue);
    final sameRam = current.evaluate(device: now, model: gemma, contextTokens: 2048);
    expect(sameRam.reusedBenchmark, isTrue);
    expect(sameRam.reasons, contains('benchmark_reused'));
    expect(sameRam.admitted, isTrue);
  });

  test('insufficient RAM rejects the model and a fitting device admits it', () {
    final tight = measured(totalRamMb: 2048, availableRamMb: 800, decode: 2.2);
    final rejected = policy.evaluate(device: tight, model: gemma, contextTokens: 2048);
    expect(rejected.admitted, isFalse);
    expect(rejected.reasons, contains('memory_budget_exceeded'));

    final fit = measured(
      totalRamMb: 8192,
      availableRamMb: 4096,
      decode: 2.4,
      peakRssMb: 1500,
    );
    final admitted = policy.evaluate(device: fit, model: gemma, contextTokens: 2048);
    expect(admitted.admitted, isTrue);
    expect(admitted.selectedContextTokens, 2048);
  });

  test('memory near the safety budget is admitted at medium or high risk', () {
    final near = measured(
      totalRamMb: 8192,
      availableRamMb: 4000,
      decode: 2.2,
      peakRssMb: 2600,
      cpuPartIds: const [0xD41],
    );
    final result = policy.evaluate(device: near, model: gemma, contextTokens: 2048);
    expect(result.admitted, isTrue);
    expect(result.riskLevel, AdmissionRisk.high);
  });

  test('A53 baseline stays Gemma 4 E4B at 2048 and 256 per stage', () {
    final device = DeviceCapabilityProfile.a53Baseline();
    expect(device.tier, DeviceTier.mid);
    expect(device.hardwareTier, HardwareTier.t2);
    expect(device.cpuClass, CpuClass.c2);
    final chosen = selection.select(
      device: device,
      request: const ModelSelectionRequest(taskType: 'text.direct'),
    );
    expect(chosen.admitted, isTrue);
    expect(chosen.selectedModelId, gemma.modelId);
    expect(chosen.selectedBackend, 'GPU/OpenCL');
    expect(chosen.selectedContextTokens, 2048);
    expect(chosen.shortOutputTokens, 256);
    expect(chosen.mediumOutputTokens, 384);
    expect(chosen.detailedOutputTokens, 512);
    expect(chosen.perStageOutput, 256);
    expect(chosen.maxStages, 6);
    expect(chosen.hardMaxStages, 8);
    expect(chosen.parallelInference, 1);
    expect(chosen.residentModels, 1);
    expect(chosen.maxImages, 1);
    expect(device.hardwareLog(), contains('[DEVICE HARDWARE]'));
    expect(device.hardwareLog(), contains('ram=6144'));
    expect(device.hardwareLog(), contains('cpuClass=c2'));
    expect(device.tierLog(), contains('[DEVICE TIER]'));
    expect(device.lookupLog(), contains('[DEVICE LOOKUP]'));
    expect(device.tierLog(), contains('ramTier=T2'));
    expect(device.tierLog(), contains('finalTier=T2'));
    expect(chosen.configLog(), contains('context=2048'));
    expect(chosen.configLog(), contains('short=256'));
    expect(chosen.configLog(), contains('medium=384'));
    expect(chosen.configLog(), contains('detailed=512'));
    expect(chosen.configLog(), contains('longStage=256'));
    expect(chosen.configLog(), contains('vision=1'));
    final wide = policy.evaluate(device: device, model: gemma, contextTokens: 4096);
    expect(wide.admitted, isFalse);
    expect(wide.reasons, contains('context_4096_without_benchmark'));
  });

  test('4096 is rejected until that context benchmark succeeds', () {
    final candidate = measured(
      availableRamMb: 9000,
      totalRamMb: 16384,
      decode: 3.2,
      peakRssMb: 2200,
      contextTokens: 3072,
      cpuPartIds: const [0xD81],
      headroom: 0.6,
    );
    expect(candidate.hardwareTier, HardwareTier.t5);
    expect(candidate.tier, DeviceTier.high);
    final blocked = policy.evaluate(device: candidate, model: gemma, contextTokens: 4096);
    expect(blocked.admitted, isFalse);
    expect(blocked.reasons, contains('context_4096_without_benchmark'));
    final base = selection.select(
      device: candidate,
      request: const ModelSelectionRequest(taskType: 'text.direct'),
    );
    expect(base.selectedContextTokens, 3072);

    final proven = measured(
      availableRamMb: 9000,
      totalRamMb: 16384,
      decode: 3.2,
      peakRssMb: 2600,
      contextTokens: 4096,
      cpuPartIds: const [0xD81],
      headroom: 0.6,
    );
    final allowed = policy.evaluate(device: proven, model: gemma, contextTokens: 4096);
    expect(allowed.admitted, isTrue);
    expect(allowed.selectedContextTokens, 4096);
    final chosen = selection.select(
      device: proven,
      request: const ModelSelectionRequest(taskType: 'text.direct'),
    );
    expect(chosen.selectedContextTokens, 4096);
    expect(chosen.hardMaxStages, 12);
  });

  test('a larger model is rejected on LOW and admitted on HIGH when memory passes', () {
    final low = measured(
      model: 'SM-A536E',
      totalRamMb: 4096,
      availableRamMb: 1800,
      decode: 1.2,
      peakRssMb: 900,
    );
    expect(low.tier, DeviceTier.low);
    final rejected = policy.evaluate(device: low, model: larger, contextTokens: 4096);
    expect(rejected.admitted, isFalse);
    expect(rejected.reasons, contains('larger_model_low_tier'));

    final high = measured(
      model: 'SM-A536E',
      totalRamMb: 16000,
      availableRamMb: 12000,
      decode: 4.5,
      peakRssMb: 5000,
      contextTokens: 4096,
      cpuPartIds: const [0xD81],
      modelSha256: larger.artifactSha256,
      headroom: 0.6,
    );
    expect(high.tier, DeviceTier.high);
    expect(low.model, high.model);
    final admitted = policy.evaluate(device: high, model: larger, contextTokens: 4096);
    expect(admitted.admitted, isTrue);
  });

  test('tier follows measured RAM and CPU parts, not the phone name', () {
    final slow = measured(
      model: 'SM-A536E',
      availableRamMb: 4000,
      totalRamMb: 6144,
      decode: 1.1,
      cpuPartIds: const [0xD03],
    );
    final fast = measured(
      model: 'SM-A536E',
      availableRamMb: 9000,
      totalRamMb: 16384,
      decode: 4.4,
      cpuPartIds: const [0xD85],
      headroom: 0.6,
    );
    expect(slow.model, fast.model);
    expect(slow.hardwareTier, HardwareTier.t1);
    expect(fast.hardwareTier, HardwareTier.t5);
    expect(slow.tier, isNot(fast.tier));
  });

  test('long-form stage limits follow the device tier', () {
    final low = selection.select(
      device: measured(availableRamMb: 1800, totalRamMb: 4096, decode: 1.2, peakRssMb: 900),
      request: const ModelSelectionRequest(taskType: 'text.direct'),
    );
    final mid = selection.select(
      device: DeviceCapabilityProfile.a53Baseline(),
      request: const ModelSelectionRequest(taskType: 'text.direct'),
    );
    final high = selection.select(
      device: measured(
        availableRamMb: 8000,
        totalRamMb: 12288,
        decode: 2.0,
        peakRssMb: 1800,
        cpuPartIds: const [0xD81],
        headroom: 0.6,
      ),
      request: const ModelSelectionRequest(taskType: 'text.direct'),
    );
    expect(low.hardMaxStages, 6);
    expect(low.selectedContextTokens, 1536);
    expect(mid.hardMaxStages, 8);
    expect(high.hardMaxStages, 10);
    expect(low.longFormBudget.maxElapsedMs, 12 * 60 * 1000);
    expect(mid.longFormBudget.maxElapsedMs, 16 * 60 * 1000);
    expect(high.longFormBudget.maxElapsedMs, 25 * 60 * 1000);
  });

  test('severe thermal blocks the next stage and normal thermal allows it', () {
    final budget = midBudget();
    final blocked = budget.evaluate(
      stageIndex: 1,
      stageCount: 1,
      signals: const LongFormRuntimeSignals(
        elapsedMs: 1000,
        leaseRemainingMs: 120000,
        batteryPercent: 80,
        thermalState: ThermalState.critical,
      ),
    );
    expect(blocked.shouldContinue, isFalse);
    expect(blocked.reason, 'thermal');
    final allowed = budget.evaluate(
      stageIndex: 1,
      stageCount: 1,
      signals: const LongFormRuntimeSignals(
        elapsedMs: 1000,
        leaseRemainingMs: 120000,
        batteryPercent: 80,
        thermalState: ThermalState.normal,
      ),
    );
    expect(allowed.shouldContinue, isTrue);
    expect(allowed.reason, 'ok');
  });

  test('a short lease blocks the next long-form stage', () async {
    const user = 'یه مقاله در مورد مورچه بده که ۵ صفحه بشه';
    final decision = GemmaGenerationOutputLimit.resolveTextDirect(prompt: user);
    final budget = midBudget(
      signals: const LongFormRuntimeSignals(
        leaseRemainingMs: 1000,
        batteryPercent: 90,
        thermalState: ThermalState.normal,
      ),
    );
    var calls = 0;
    final result = await GemmaStagedDirectGeneration.run(
      decision: decision,
      prompt: user,
      executionBudget: budget,
      generateStage: (stageIndex, stagePrompt) async {
        calls += 1;
        return const GemmaStagePiece(
          text: 'کلونی را',
          stopReason: GemmaGenerationOutputLimit.outputLimit,
          generatedChunks: 256,
          generatedTokens: 40,
        );
      },
    );
    expect(calls, 1);
    expect(result.complete, isFalse);
    expect(result.truncated, isTrue);
    expect(result.stopReason, GemmaGenerationOutputLimit.longFormStageLimit);
    final gate = budget.evaluate(
      stageIndex: 1,
      stageCount: 1,
      signals: budget.initialSignals,
    );
    expect(gate.shouldContinue, isFalse);
    expect(gate.reason, 'lease');
  });

  test('runtime health can lower the stage ceiling without a new admission', () {
    final budget = midBudget();
    final degraded = budget.degrade(
      const RuntimeHealthSample(
        decodeChunksPerSecond: 0.4,
        baselineDecodeChunksPerSecond: 2.3,
        thermalState: ThermalState.throttled,
      ),
    );
    expect(degraded.hardMaxStages, lessThan(budget.hardMaxStages));
    expect(degraded.multimodalEligible, isFalse);
  });

  test('admission cache is reused until the runtime version changes', () {
    final cache = AdmissionResultCache();
    final first = ModelAdmissionPolicy(cache: cache);
    final device = DeviceCapabilityProfile.a53Baseline();
    final admitted = first.evaluate(device: device, model: gemma, contextTokens: 2048);
    expect(admitted.admitted, isTrue);
    final reused = first.evaluate(device: device, model: gemma, contextTokens: 2048);
    expect(reused.reusedBenchmark, isTrue);

    const nextRuntime = ModelAdmissionPolicy(
      config: DeviceInferencePolicyConfig(runtimeVersion: 'litert-lm-next'),
    );
    final fresh = ModelAdmissionPolicy(cache: cache, config: nextRuntime.config);
    final again = fresh.evaluate(device: device, model: gemma, contextTokens: 2048);
    expect(again.reusedBenchmark, isFalse);
  });

  test('an OOM block is not retried until available RAM improves', () {
    final cache = AdmissionResultCache();
    final admission = ModelAdmissionPolicy(cache: cache);
    final failed = measured(
      availableRamMb: 3000,
      totalRamMb: 6144,
      decode: 2.0,
      nativeOom: true,
      contextTokens: 2048,
    );
    final first = admission.evaluate(device: failed, model: gemma, contextTokens: 2048);
    expect(first.admitted, isFalse);
    expect(first.reasons, contains('native_oom'));
    final retry = admission.evaluate(
      device: failed.copyWith(benchmark: const DeviceBenchmarkMetrics(
        engineLoadMs: 1000,
        decodeChunksPerSecond: 2.0,
        contextTokens: 2048,
        peakRssMb: 1400,
      )),
      model: gemma,
      contextTokens: 2048,
    );
    expect(retry.admitted, isFalse);
    expect(retry.reasons, contains('oom_blocked_no_meaningful_change'));
    final improved = admission.evaluate(
      device: failed.copyWith(
        availableRamMb: 3600,
        benchmark: const DeviceBenchmarkMetrics(
          engineLoadMs: 1000,
          decodeChunksPerSecond: 2.2,
          contextTokens: 2048,
          peakRssMb: 1400,
        ),
      ),
      model: gemma,
      contextTokens: 2048,
    );
    expect(improved.reasons, isNot(contains('oom_blocked_no_meaningful_change')));
    expect(improved.admitted, isTrue);
  });

  test('a file cache round-trips an admission result', () {
    final dir = Directory.systemTemp.createTempSync('edgemint-admission');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = FileAdmissionCacheStore(File('${dir.path}/model_admission_cache.json'));
    final cache = AdmissionResultCache(store: store);
    const saved = ModelAdmissionResult(
      admitted: true,
      selectedBackend: 'GPU/OpenCL',
      selectedContextTokens: 2048,
      riskLevel: AdmissionRisk.medium,
      reasons: ['admitted'],
      modelId: 'mdv_gemma_4_e4b_it_gpu',
    );
    cache.write(
      fingerprint: 'device',
      modelSha256: gemma.artifactSha256,
      runtimeVersion: 'litert-lm-gemma4',
      appVersion: 'dev',
      contextTokens: 2048,
      availableRamMb: 2960,
      totalRamMb: 7398,
      maxFreeResourceFraction: 0.75,
      result: saved,
    );
    final restored = AdmissionResultCache(
      store: FileAdmissionCacheStore(File('${dir.path}/model_admission_cache.json')),
    ).read(
      fingerprint: 'device',
      modelSha256: gemma.artifactSha256,
      runtimeVersion: 'litert-lm-gemma4',
      appVersion: 'dev',
      contextTokens: 2048,
      availableRamMb: 2960,
      totalRamMb: 7398,
      maxFreeResourceFraction: 0.75,
    );
    expect(restored?.admitted, isTrue);
    expect(restored?.selectedContextTokens, 2048);
    expect(
      AdmissionResultCache(
        store: FileAdmissionCacheStore(File('${dir.path}/model_admission_cache.json')),
      ).read(
        fingerprint: 'device',
        modelSha256: gemma.artifactSha256,
        runtimeVersion: 'other-runtime',
        appVersion: 'dev',
        contextTokens: 2048,
        availableRamMb: 2960,
        totalRamMb: 7398,
        maxFreeResourceFraction: 0.75,
      ),
      isNull,
    );
  });

  test('case 1: 3GB and CPU class 0 stay on T0 with context 1024', () {
    final device = measured(
      totalRamMb: 3 * 1024,
      availableRamMb: 2200,
      cpuPartIds: const [0xD03],
    );
    expect(device.ramTier, RamTier.t0);
    expect(device.cpuClass, CpuClass.c0);
    expect(device.hardwareTier, HardwareTier.t0);
    final chosen = selection.select(
      device: device,
      request: const ModelSelectionRequest(taskType: 'text.direct'),
    );
    expect(chosen.selectedContextTokens, 1024);
    expect(chosen.shortOutputTokens, 128);
  });

  test('case 2: 6GB RAM and CPU class 0 resolve to T1', () {
    final device = measured(
      totalRamMb: 6 * 1024,
      availableRamMb: 4000,
      decode: 1.4,
      cpuPartIds: const [0xD05],
    );
    expect(device.ramTier, RamTier.t2);
    expect(device.cpuClass, CpuClass.c0);
    expect(device.cpuTier, HardwareTier.t1);
    expect(device.hardwareTier, HardwareTier.t1);
    final chosen = selection.select(
      device: device,
      request: const ModelSelectionRequest(taskType: 'text.direct'),
    );
    expect(chosen.selectedContextTokens, 1536);
    expect(chosen.hardwareTier, HardwareTier.t1);
  });

  test('case 3: 6GB and CPU class 2 select T2 and admit E4B', () {
    final device = measured(
      totalRamMb: 6 * 1024,
      availableRamMb: 3200,
      decode: 2.3,
      peakRssMb: 1500,
      cpuPartIds: const [0xD41],
    );
    expect(device.hardwareTier, HardwareTier.t2);
    final admitted = policy.evaluate(device: device, model: gemma, contextTokens: 2048);
    expect(admitted.admitted, isTrue);
    final chosen = selection.select(
      device: device,
      request: const ModelSelectionRequest(taskType: 'text.direct'),
    );
    expect(chosen.selectedModelId, gemma.modelId);
    expect(chosen.selectedContextTokens, 2048);
    expect(chosen.perStageOutput, 256);
    expect(chosen.maxStages, 6);
    expect(chosen.hardMaxStages, 8);
  });

  test('case 4: 12GB RAM and CPU class 1 stay at T2, not high', () {
    final device = measured(
      totalRamMb: 12 * 1024,
      availableRamMb: 7000,
      decode: 2.4,
      cpuPartIds: const [0xD0A],
    );
    expect(device.ramTier, RamTier.t4);
    expect(device.cpuClass, CpuClass.c1);
    expect(device.cpuTier, HardwareTier.t2);
    expect(device.hardwareTier, HardwareTier.t2);
    expect(device.tier, isNot(DeviceTier.high));
    final chosen = selection.select(
      device: device,
      request: const ModelSelectionRequest(taskType: 'text.direct'),
    );
    expect(chosen.selectedContextTokens, 2048);
    expect(chosen.selectedModelId, gemma.modelId);
  });

  test('case 5: 8GB and CPU class 3 select T3', () {
    final device = measured(
      totalRamMb: 8 * 1024,
      availableRamMb: 5000,
      decode: 2.5,
      cpuPartIds: const [0xD4D],
    );
    expect(device.ramTier, RamTier.t3);
    expect(device.cpuClass, CpuClass.c3);
    expect(device.hardwareTier, HardwareTier.t3);
    final chosen = selection.select(
      device: device,
      request: const ModelSelectionRequest(taskType: 'text.direct'),
    );
    expect(chosen.selectedContextTokens, 2048);
    expect(chosen.hardMaxStages, 8);
  });

  test('case 6: 16GB and CPU class 4 are a T5 candidate and 4096 needs a benchmark', () {
    final device = measured(
      totalRamMb: 16 * 1024,
      availableRamMb: 9000,
      decode: 3.2,
      peakRssMb: 2200,
      contextTokens: 3072,
      cpuPartIds: const [0xD82],
    );
    expect(device.hardwareTier, HardwareTier.t5);
    final chosen = selection.select(
      device: device,
      request: const ModelSelectionRequest(taskType: 'text.direct'),
    );
    expect(chosen.selectedContextTokens, 3072);
    final wide = policy.evaluate(device: device, model: gemma, contextTokens: 4096);
    expect(wide.admitted, isFalse);
    expect(wide.reasons, contains('context_4096_without_benchmark'));
  });

  test('case 7: low available RAM keeps the capability tier and downgrades runtime', () {
    final device = measured(
      totalRamMb: 12 * 1024,
      availableRamMb: 1500,
      decode: 4.0,
      cpuPartIds: const [0xD81],
    );
    expect(device.ramTier, RamTier.t4);
    expect(device.hardwareTier, HardwareTier.t4);
    final admitted = policy.evaluate(device: device, model: gemma, contextTokens: 2048);
    expect(admitted.admitted, isFalse);
    expect(admitted.reasons, contains('memory_budget_exceeded'));
    final budget = const TierPolicyTable().t4;
    final degraded = LongFormExecutionBudget(
      maxStages: budget.maxStages,
      hardMaxStages: budget.hardMaxStages,
      maxElapsedMs: budget.maxElapsedMs,
      minimumLeaseRemainingMs: budget.minimumLeaseRemainingMs,
      minimumBatteryPercent: budget.minimumBatteryPercent,
      maximumThermalState: budget.maximumThermalState,
      multimodalEligible: true,
    ).degrade(
      const RuntimeHealthSample(availableRamMb: 1500),
    );
    expect(degraded.hardMaxStages, lessThan(budget.hardMaxStages));
    expect(degraded.multimodalEligible, isFalse);
  });

  test('case 8: unknown CPU never exceeds T2 without a benchmark', () {
    final device = measured(
      totalRamMb: 16 * 1024,
      availableRamMb: 9000,
      decode: 4.8,
    );
    expect(device.cpuClass, CpuClass.unknown);
    expect(device.cpuTier, HardwareTier.t2);
    expect(device.hardwareTier, HardwareTier.t2);
    expect(device.tier, isNot(DeviceTier.high));
    final chosen = selection.select(
      device: device,
      request: const ModelSelectionRequest(taskType: 'text.direct'),
    );
    expect(chosen.selectedContextTokens, lessThanOrEqualTo(2048));
  });
}

LongFormExecutionBudget midBudget({LongFormRuntimeSignals? signals}) {
  return LongFormExecutionBudget(
    maxStages: 6,
    hardMaxStages: 8,
    maxElapsedMs: 20 * 60 * 1000,
    minimumLeaseRemainingMs: 60000,
    minimumBatteryPercent: 20,
    maximumThermalState: ThermalState.warm,
    multimodalEligible: true,
    initialSignals: signals ?? const LongFormRuntimeSignals(),
  );
}
