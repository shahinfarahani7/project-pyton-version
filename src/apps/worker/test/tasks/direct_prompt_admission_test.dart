import 'package:edgemint_worker/contracts/worker_error.dart';
import 'package:edgemint_worker/contracts/worker_task_request.dart';
import 'package:edgemint_worker/contracts/worker_task_result.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/ocr/fake_ocr_engine.dart';
import 'package:edgemint_worker/runtime/device_capability_profile.dart';
import 'package:edgemint_worker/runtime/device_inference_plan.dart';
import 'package:edgemint_worker/runtime/device_snapshot.dart';
import 'package:edgemint_worker/runtime/gemma_generation_output_limit.dart';
import 'package:edgemint_worker/runtime/memory_sample.dart';
import 'package:edgemint_worker/runtime/model_admission_policy.dart';
import 'package:edgemint_worker/runtime/model_selection_policy.dart';
import 'package:edgemint_worker/tasks/handlers/direct_prompt_handler.dart';
import 'package:edgemint_worker/telemetry/worker_task_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const gemma = InferenceModelCatalog.gemma4E4bGpu;
  final plan = DeviceInferencePlan.instance;

  setUp(() {
    plan.debugReset();
    plan.clock = () => DateTime.utc(2026, 11, 15, 8);
    plan.publish(
      DeviceCapabilityProfile(
        manufacturer: 'Samsung',
        model: 'SM-A515F',
        totalRamMb: 7398,
        availableRamMb: 5000,
        cpuArchitecture: 'arm64-v8a',
        cpuPartIds: const [0xD41],
        gpuAvailable: true,
        gpuBackend: 'OpenCL',
        thermalState: ThermalState.normal,
      ),
    );
    plan.readResidentEngine = () => ResidentEngineIdentity(
          modelVersionId: gemma.modelId,
          modelSha256: gemma.artifactSha256,
          backend: gemma.preferredBackend,
          contextTokens: 2048,
          runtimeVersion: plan.config.runtimeVersion,
          healthy: true,
        );
  });

  tearDown(plan.debugReset);

  DeviceSnapshot snapshot(int availableRamMb) => DeviceSnapshot(
        available: true,
        batteryPercent: 80,
        isCharging: false,
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

  Future<WorkerTaskResult> handle(
    DirectPromptHandler handler, {
    bool longForm = false,
  }) {
    return handler.handle(
      request: WorkerTaskRequest(
        schemaVersion: '1',
        taskId: 'tsk_dev_5485d66e',
        idempotencyKey: 'idem',
        type: 'text.direct.v1',
        sourceTaskType: 'text.direct',
        input: const WorkerTaskInput(text: 'Say hello'),
        options: WorkerTaskOptions(longForm: longForm),
      ),
      ocrEngine: FakeOcrEngine(),
      qwenProcessor: QwenTaskProcessor(),
      signingKey: 'test-key',
      metrics: WorkerTaskMetrics(),
    );
  }

  test('generation does not start when the fresh sample is short', () async {
    plan.readMemorySample = () async => MemorySample.measured(
          snapshot(672),
          sampledAt: plan.clock(),
        );
    var calls = 0;
    final handler = DirectPromptHandler(
      plan: plan,
      runStage: (stage, prompt, limit, sampling) async {
        calls += 1;
        return const GemmaStagePiece(
          text: 'Hello.',
          stopReason: 'model_eos',
          generatedChunks: 1,
          generatedTokens: 1,
        );
      },
    );
    await expectLater(
      handle(handler),
      throwsA(
        isA<WorkerError>()
            .having((error) => error.code, 'code', WorkerErrorCode.outOfMemoryRisk)
            .having((error) => error.message, 'message', contains('Memory budget'))
            .having((error) => error.message, 'message', isNot(contains('Free RAM'))),
      ),
    );
    expect(calls, 0);
  });

  test('a fresh sufficient sample uses that decision for the stage settings', () async {
    plan.readMemorySample = () async => MemorySample.measured(
          snapshot(5000),
          sampledAt: plan.clock(),
        );
    int? seenLimit;
    final handler = DirectPromptHandler(
      plan: plan,
      runStage: (stage, prompt, limit, sampling) async {
        seenLimit = limit;
        expect(sampling, isNotNull);
        return const GemmaStagePiece(
          text: 'Hello.',
          stopReason: 'model_eos',
          generatedChunks: 1,
          generatedTokens: 1,
        );
      },
    );
    final result = await handle(handler);
    expect(result.status.name, 'succeeded');
    final decision = await plan.reevaluate(
      taskType: 'text.direct',
      wantsVision: false,
    );
    expect(seenLimit, decision!.selectedOutputLimit('short'));
    expect(decision.selectedContextTokens, 2048);
  });

  test('a later stage sees a fresh short sample and does not continue', () async {
    var reads = 0;
    plan.readMemorySample = () async {
      reads += 1;
      final available = reads == 1 ? 5000 : 672;
      return MemorySample.measured(
        snapshot(available),
        sampledAt: plan.clock(),
      );
    };
    var calls = 0;
    final handler = DirectPromptHandler(
      plan: plan,
      runStage: (stage, prompt, limit, sampling) async {
        calls += 1;
        return const GemmaStagePiece(
          text: 'still going',
          stopReason: 'output_limit',
          generatedChunks: 1,
          generatedTokens: 2,
        );
      },
    );
    await expectLater(
      handle(handler, longForm: true),
      throwsA(isA<WorkerError>().having(
        (error) => error.code,
        'code',
        WorkerErrorCode.outOfMemoryRisk,
      )),
    );
    expect(calls, 1);
  });
}
