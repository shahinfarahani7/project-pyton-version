import 'dart:async';

import 'package:edgemint_worker/inference/ocr/fake_ocr_engine.dart';
import 'package:edgemint_worker/inference/ocr/guarded_ocr_engine.dart';
import 'package:edgemint_worker/runtime/execution_plan_runner.dart';
import 'package:edgemint_worker/runtime/model_runtime_manager.dart';
import 'package:edgemint_worker/runtime/device_snapshot.dart';
import 'package:edgemint_worker/runtime/runtime_exclusive_group_enforcer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RuntimeExclusiveGroupEnforcer', () {
    test('ocr waits while heavy llm session is active by default', () async {
      final enforcer = RuntimeExclusiveGroupEnforcer();
      final heavyEntered = Completer<void>();
      final releaseHeavy = Completer<void>();
      var ocrStartedWhileHeavy = false;

      final heavyFuture = enforcer.withHeavyLlmInference(() async {
        heavyEntered.complete();
        await releaseHeavy.future;
        return 'heavy';
      });

      await heavyEntered.future;

      final ocrFuture = enforcer.withOcrInference(() async {
        ocrStartedWhileHeavy = enforcer.heavyLlmActive;
        return 'ocr';
      });

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ocrFuture.isCompleted, isFalse);

      releaseHeavy.complete();
      await Future.wait([heavyFuture, ocrFuture]);
      expect(ocrStartedWhileHeavy, isFalse);
    });

    test('certified profile allows concurrent ocr during heavy llm', () async {
      final enforcer = RuntimeExclusiveGroupEnforcer(
        llmOcrConcurrentCertified: true,
      );
      final heavyEntered = Completer<void>();
      final releaseHeavy = Completer<void>();
      var ocrStartedWhileHeavy = false;

      unawaited(enforcer.withHeavyLlmInference(() async {
        heavyEntered.complete();
        await releaseHeavy.future;
      }));

      await heavyEntered.future;
      await enforcer.withOcrInference(() async {
        ocrStartedWhileHeavy = enforcer.heavyLlmActive;
      });

      expect(ocrStartedWhileHeavy, isTrue);
      releaseHeavy.complete();
    });

    test('thermal throttling reduces certified ocr concurrency limit', () {
      final enforcer = RuntimeExclusiveGroupEnforcer(
        llmOcrConcurrentCertified: true,
        certifiedMaxOcrSessions: 2,
      );
      enforcer.updateThermalState(ThermalState.warm);
      expect(enforcer.maxOcrSessions, 1);
    });

    test('guarded ocr engine serializes recognize through enforcer', () async {
      final enforcer = RuntimeExclusiveGroupEnforcer();
      final engine = GuardedOcrEngine(
        delegate: FakeOcrEngine(),
        exclusiveGroups: enforcer,
      );

      unawaited(enforcer.withHeavyLlmInference(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }));

      await Future<void>.delayed(const Duration(milliseconds: 5));
      final started = Stopwatch()..start();
      await engine.recognize(imageBytes: [1, 2, 3]);
      expect(started.elapsed.inMilliseconds, greaterThanOrEqualTo(30));
    });

    test('execution plan ocr stage uses exclusive group enforcer', () async {
      final enforcer = RuntimeExclusiveGroupEnforcer();
      final memory = InMemoryModelRuntimeManager(
        verifyArtifact: false,
        exclusiveGroupEnforcer: enforcer,
      );
      final runner = ExecutionPlanRunner(
        modelRuntime: memory,
        exclusiveGroupEnforcer: enforcer,
      );
      var ocrStageCompleted = false;

      unawaited(enforcer.withHeavyLlmInference(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }));
      await Future<void>.delayed(const Duration(milliseconds: 5));

      final started = Stopwatch()..start();
      runner.enterAssignmentScope(assignmentId: 'asg', fenceToken: 1);
      await runner.runStage(
        stage: const ExecutionPlanStage(
          sequence: 1,
          name: 'ocr-document',
          operation: 'ocr',
          runtimeClass: 'paddle_ocr',
        ),
        body: () async {
          ocrStageCompleted = true;
        },
      );
      runner.exitAssignment();

      expect(ocrStageCompleted, isTrue);
      expect(started.elapsed.inMilliseconds, greaterThanOrEqualTo(25));
    });
  });
}
