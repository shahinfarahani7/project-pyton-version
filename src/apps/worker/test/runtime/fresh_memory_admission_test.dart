import 'package:edgemint_worker/runtime/device_capability_profile.dart';
import 'package:edgemint_worker/runtime/device_inference_plan.dart';
import 'package:edgemint_worker/runtime/device_snapshot.dart';
import 'package:edgemint_worker/runtime/memory_sample.dart';
import 'package:edgemint_worker/runtime/model_admission_policy.dart';
import 'package:edgemint_worker/runtime/model_selection_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const gemma = InferenceModelCatalog.gemma4E4bGpu;
  final plan = DeviceInferencePlan.instance;

  setUp(() {
    plan.debugReset();
    final cached = DeviceCapabilityProfile(
      manufacturer: 'Samsung',
      model: 'SM-A515F',
      totalRamMb: 7398,
      availableRamMb: 5000,
      cpuArchitecture: 'arm64-v8a',
      cpuPartIds: const [0xD41],
      gpuAvailable: true,
      gpuBackend: 'OpenCL',
      thermalState: ThermalState.normal,
      benchmark: DeviceBenchmarkMetrics(
        decodeChunksPerSecond: 2.4,
        contextTokens: 2048,
        modelSha256: gemma.artifactSha256,
      ),
    );
    plan.publish(cached);
    plan.readResidentEngine = () => ResidentEngineIdentity(
          modelVersionId: gemma.modelId,
          modelSha256: gemma.artifactSha256,
          backend: gemma.preferredBackend,
          contextTokens: 2048,
          runtimeVersion: plan.config.runtimeVersion,
          healthy: true,
        );
    plan.clock = () => DateTime.utc(2026, 11, 15, 8);
  });

  tearDown(plan.debugReset);

  DeviceSnapshot snapshot({required int availableRamMb}) {
    return DeviceSnapshot(
      available: true,
      batteryPercent: 80,
      isCharging: true,
      thermalState: ThermalState.normal,
      network: NetworkKind.wifi,
      freeStorageMb: 8000,
      withinSchedule: true,
      consentsGranted: const ['terms'],
      deviceTotalRamMb: 7398,
      deviceAvailableRamMb: availableRamMb,
      cpuPartIds: const [0xD41],
      cpuArchitecture: 'arm64-v8a',
    );
  }

  test('a stale sufficient profile does not start generation when the fresh sample is short', () async {
    final benchmark = plan.profile!.benchmark;
    plan.readMemorySample = () async => MemorySample.measured(
          snapshot(availableRamMb: 672),
          sampledAt: plan.clock(),
          source: 'injected',
        );
    final decision = await plan.reevaluate(
      taskType: 'text.direct',
      wantsVision: false,
    );
    expect(decision, isNotNull);
    expect(decision!.admitted, isFalse);
    expect(decision.reasonCodes, contains('resident_generation_exceeds_free_ram'));
    expect(plan.profile!.benchmark, same(benchmark));
  });

  test('a fresh sufficient sample admits the loaded engine', () async {
    plan.readMemorySample = () async => MemorySample.measured(
          snapshot(availableRamMb: 5000),
          sampledAt: plan.clock(),
          source: 'injected',
        );
    final decision = await plan.reevaluate(
      taskType: 'text.direct',
      wantsVision: false,
    );
    expect(decision!.admitted, isTrue);
    expect(decision.selectedContextTokens, 2048);
    expect(decision.reasonCodes, contains('resident_model_reuse'));
  });

  test('a stale sample is an explicit rejection', () async {
    plan.readMemorySample = () async => MemorySample(
          snapshot: snapshot(availableRamMb: 5000),
          sampledAt: plan.clock().subtract(const Duration(minutes: 2)),
          freshness: MemorySampleFreshness.fresh,
          source: 'injected',
        );
    final decision = await plan.reevaluate(
      taskType: 'text.direct',
      wantsVision: false,
    );
    expect(decision!.admitted, isFalse);
    expect(decision.reasonCodes, contains('memory_snapshot_stale'));
    expect(decision.memoryBudgetMb, isNull);
  });

  test('a missing reader does not reuse cached RAM', () async {
    final decision = await plan.reevaluate(
      taskType: 'text.direct',
      wantsVision: false,
    );
    expect(decision!.admitted, isFalse);
    expect(decision.reasonCodes, ['memory_snapshot_unknown']);
  });
}
