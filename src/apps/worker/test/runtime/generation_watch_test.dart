import 'dart:async';

import 'package:edgemint_worker/contracts/worker_error.dart';
import 'package:edgemint_worker/runtime/device_snapshot.dart';
import 'package:edgemint_worker/runtime/gemma_generation_output_limit.dart';
import 'package:edgemint_worker/runtime/generation_watch.dart';
import 'package:edgemint_worker/runtime/runtime_safety_controller.dart';
import 'package:edgemint_worker/runtime/worker_inference_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(WorkerInferenceGate.instance.debugReset);
  tearDown(WorkerInferenceGate.instance.debugReset);

  GenerationWatch watch({
    Duration? silence,
    Duration? prefill,
    Duration? confirm,
    Future<RuntimeSafetyVerdict> Function()? readSafety,
  }) {
    return GenerationWatch(
      pollInterval: const Duration(milliseconds: 15),
      silenceTimeout: silence ?? const Duration(hours: 1),
      prefillTimeout: prefill ?? const Duration(hours: 1),
      overallDeadline: const Duration(hours: 1),
      stopConfirmationTimeout: confirm ?? const Duration(milliseconds: 200),
      confirmNativeStop: true,
      readSafety: readSafety,
    );
  }

  test('cancellation during a silent stream stops generation', () async {
    final controller = StreamController<GemmaDecodePiece>();
    var stopped = false;
    final decode = await GemmaChunkGeneration.collect(
      pieces: controller.stream,
      configuredOutputLimit: 32,
      shouldContinue: () => false,
      onStop: () async {
        stopped = true;
        await controller.close();
      },
      watch: watch(),
    );
    expect(stopped, isTrue);
    expect(decode.stopReason, GemmaGenerationOutputLimit.cancelled);
    expect(decode.text, isEmpty);
  });

  test('silence after the first token stops without waiting for another token', () async {
    final controller = StreamController<GemmaDecodePiece>();
    var stopped = false;
    final pending = GemmaChunkGeneration.collect(
      pieces: controller.stream,
      configuredOutputLimit: 32,
      shouldContinue: () => true,
      onStop: () async {
        stopped = true;
        await controller.close();
      },
      watch: watch(silence: const Duration(milliseconds: 40)),
    );
    controller.add(const GemmaDecodePiece('Hello'));
    final decode = await pending;
    expect(stopped, isTrue);
    expect(decode.text, 'Hello');
    expect(decode.stopReason, 'output_silence');
  });

  test('an unconfirmed native stop refuses the next task', () async {
    final controller = StreamController<GemmaDecodePiece>();
    addTearDown(controller.close);
    await expectLater(
      GemmaChunkGeneration.collect(
        pieces: controller.stream,
        configuredOutputLimit: 32,
        shouldContinue: () => false,
        onStop: () async {},
        watch: watch(confirm: const Duration(milliseconds: 40)),
      ),
      throwsA(isA<GenerationStopUnconfirmed>()),
    );
    WorkerInferenceGate.instance.markStopUnconfirmed('output_silence');
    expect(WorkerInferenceGate.instance.acceptsWork, isFalse);
    expect(
      WorkerInferenceGate.instance.ensureAcceptsWork,
      throwsA(isA<WorkerError>().having(
        (error) => error.retryable,
        'retryable',
        isFalse,
      )),
    );
  });

  test('a memory drop during a silent stream stops generation', () async {
    final controller = StreamController<GemmaDecodePiece>();
    final decode = await GemmaChunkGeneration.collect(
      pieces: controller.stream,
      configuredOutputLimit: 32,
      shouldContinue: () => true,
      onStop: () async {
        await controller.close();
      },
      watch: watch(
        readSafety: () async => evaluateLiveMemory(
          const RuntimeSafetyController(),
          const DeviceSnapshot(
            available: true,
            batteryPercent: 80,
            isCharging: true,
            thermalState: ThermalState.normal,
            network: NetworkKind.wifi,
            freeStorageMb: 4000,
            withinSchedule: true,
            consentsGranted: ['terms'],
            deviceAvailableRamMb: 100,
            deviceTotalRamMb: 4096,
          ),
        ),
      ),
    );
    expect(decode.stopReason, 'memory_pressure');
  });
}
