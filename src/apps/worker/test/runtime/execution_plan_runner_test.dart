import 'dart:async';

import 'package:edgemint_worker/runtime/device_snapshot.dart';
import 'package:edgemint_worker/runtime/execution_plan_runner.dart';
import 'package:edgemint_worker/runtime/inference_adapter.dart';
import 'package:edgemint_worker/runtime/model_runtime_manager.dart';
import 'package:edgemint_worker/runtime/runtime_exceptions.dart';
import 'package:edgemint_worker/runtime/runtime_safety_controller.dart';
import 'package:edgemint_worker/runtime/worker_resource_budget.dart';
import 'package:edgemint_worker/runtime/worker_resource_enforcer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:edgemint_worker/api/worker_assignment_models.dart';
import 'dart:typed_data';

WorkerAssignment _assignment({int fenceToken = 3}) => WorkerAssignment(
      assignmentId: 'asg_test',
      attemptId: 'att_test',
      revisionId: 'rev_test',
      leaseToken: 'lease_test',
      fenceToken: fenceToken,
      leaseExpiresAt: DateTime.parse('2026-07-26T14:00:00Z'),
      taskType: 'text.summarize',
      modelVersionId: 'mdv_test',
      inputManifestUrl: 'https://example/input',
      outputUploadUrl: 'https://example/output',
      startDeadlineAt: DateTime.parse('2026-07-26T13:30:00Z'),
    );

const _healthySnapshot = DeviceSnapshot(
  available: true,
  batteryPercent: 80,
  isCharging: true,
  thermalState: ThermalState.normal,
  network: NetworkKind.wifi,
  freeStorageMb: 4096,
  withinSchedule: true,
  consentsGranted: ['compute'],
);

Future<void> _loadModel(InMemoryModelRuntimeManager memory) {
  return memory.ensureResident(
    artifact:  ModelArtifact(
      modelVersionId: 'mdv-qwen',
      digestSha256: 'digest',
      signatureSha256: 'sig',
      backend: InferenceBackend.liteRt,
      bytes: Uint8List.fromList([1]),
    ),
    signingKey: 'sign',
  );
}

void main() {
  group('ExecutionPlanRunner', () {
    test('rejects stale fence on assignment entry', () {
      final runner = ExecutionPlanRunner(
        modelRuntime: InMemoryModelRuntimeManager(verifyArtifact: false),
      );
      runner.enterAssignment(_assignment(fenceToken: 2));
      expect(
        () => runner.enterAssignment(_assignment(fenceToken: 3)),
        throwsA(isA<StaleFenceException>()),
      );
    });

    test('runStage opens and closes a fresh session per llm stage', () async {
      final memory = InMemoryModelRuntimeManager(verifyArtifact: false);
      await _loadModel(memory);
      final runner = ExecutionPlanRunner(modelRuntime: memory);
      runner.enterAssignment(_assignment());

      await runner.runStage(
        stage: const ExecutionPlanStage(
          sequence: 1,
          name: 'llm-summarize',
          operation: 'llm_infer',
          runtimeClass: 'mediapipe_llm',
        ),
        body: () async => 'ok',
      );

      expect(memory.sessionCount, 1);
      expect(memory.openSessionCount, 0);
      runner.exitAssignment();
      expect(runner.boundAssignmentId, isNull);
    });

    test('exitAssignment detects session leaks across assignments', () async {
      final memory = InMemoryModelRuntimeManager(verifyArtifact: false);
      await _loadModel(memory);
      final runner = ExecutionPlanRunner(modelRuntime: memory);
      runner.enterAssignment(_assignment());

      final gate = Completer<void>();
      final pending = memory.withFreshSession(
        stageId: 'leaked',
        body: () async {
          await gate.future;
        },
      );

      expect(memory.openSessionCount, 1);
      expect(() => runner.exitAssignment(), throwsStateError);

      gate.complete();
      await pending;
      runner.exitAssignment();
      expect(memory.openSessionCount, 0);
    });

    test('runPlan executes stages in order and clears binding', () async {
      final memory = InMemoryModelRuntimeManager(verifyArtifact: false);
      await _loadModel(memory);
      final runner = ExecutionPlanRunner(modelRuntime: memory);
      final plan = ExecutionPlanCatalog.forTaskType('text.classify');
      final order = <String>[];

      await runner.runPlan(
        plan: plan,
        assignment: _assignment(),
        executeStage: (stage) async {
          order.add(stage.name);
          return stage.name;
        },
      );

      expect(order, ['llm-classify', 'validate', 'submit']);
      expect(runner.boundAssignmentId, isNull);
      expect(memory.openSessionCount, 0);
      expect(memory.sessionCount, 1);
    });

    test('runPlan emits monotonic progress events for multi-stage summarize plan', () async {
      final memory = InMemoryModelRuntimeManager(verifyArtifact: false);
      await _loadModel(memory);
      final runner = ExecutionPlanRunner(modelRuntime: memory);
      final plan = ExecutionPlanCatalog.forTaskType('text.summarize');
      final progress = <int>[];

      await runner.runPlan(
        plan: plan,
        assignment: _assignment(),
        context: ExecutionPlanRunContext(
          deviceSnapshot: _healthySnapshot,
          onProgress: (event) async {
            progress.add(event.progressMilli);
          },
        ),
        executeStage: (stage) async => stage.name,
      );

      expect(plan.stages.map((stage) => stage.name).toList(), [
        'chunk',
        'llm-map',
        'llm-reduce',
        'validate',
        'submit',
      ]);
      expect(progress, [200, 400, 600, 800, 1000]);
    });

    test('runPlan blocks llm stage when safety rejects device snapshot', () async {
      final memory = InMemoryModelRuntimeManager(verifyArtifact: false);
      await _loadModel(memory);
      const safety = RuntimeSafetyController();
      final runner = ExecutionPlanRunner(
        modelRuntime: memory,
        safetyController: safety,
      );
      final plan = ExecutionPlanCatalog.forTaskType('text.classify');

      expect(
        () => runner.runPlan(
          plan: plan,
          assignment: _assignment(),
          context: ExecutionPlanRunContext(
            deviceSnapshot: _healthySnapshot.copyWith(
              thermalState: ThermalState.critical,
            ),
            safetyController: safety,
          ),
          executeStage: (stage) async => stage.name,
        ),
        throwsA(isA<RuntimeSafetyException>()),
      );
    });

    test('runPlan blocks llm stage when resource enforcer rejects request', () async {
      final memory = InMemoryModelRuntimeManager(verifyArtifact: false);
      await _loadModel(memory);
      final enforcer = WorkerResourceEnforcer(
        capacity: const DeviceResourceCapacity(
          cpuUnits: 1000,
          totalRamBytes: 8 * 1024 * 1024 * 1024,
          availableRamBytes: 4 * 1024 * 1024 * 1024,
          safetyReserveBytes: 512 * 1024 * 1024,
          storageAvailableBytes: 8 * 1024 * 1024 * 1024,
          storageMinimumFreeBytes: 512 * 1024 * 1024,
          maxAiStorageBytes: 2 * 1024 * 1024 * 1024,
        ),
      );
      final runner = ExecutionPlanRunner(
        modelRuntime: memory,
        resourceEnforcer: enforcer,
      );
      final plan = ExecutionPlanCatalog.forTaskType('text.classify');

      expect(
        () => runner.runPlan(
          plan: plan,
          assignment: _assignment(),
          context: ExecutionPlanRunContext(
            resourceEnforcer: enforcer,
            stageResourceRequest: ResourceClassTotals(
              cpuUnits: enforcer.effectiveBudgets.cpuUnits + 1,
              memoryBytes: 0,
              storageBytes: 0,
            ),
          ),
          executeStage: (stage) async => stage.name,
        ),
        throwsA(isA<WorkerResourceEnforcementException>()),
      );
    });
  });
}
