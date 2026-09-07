import 'dart:async';

import '../api/worker_assignment_models.dart';
import '../tasks/task_type_mapper.dart';
import 'device_snapshot.dart';
import 'model_runtime_manager.dart';
import 'runtime_exceptions.dart';
import 'runtime_safety_controller.dart';
import 'runtime_exclusive_group_enforcer.dart';
import 'vision_runtime_catalog.dart';
import 'worker_resource_budget.dart';
import 'worker_resource_enforcer.dart';

class ExecutionPlanStage {
  const ExecutionPlanStage({
    required this.sequence,
    required this.name,
    required this.operation,
    this.runtimeClass,
    this.checkpointEnabled = false,
  });

  final int sequence;
  final String name;
  final String operation;
  final String? runtimeClass;
  final bool checkpointEnabled;

  bool get requiresFreshSession =>
      operation.startsWith('llm_') ||
      operation == 'llm_infer' ||
      operation == 'vlm_infer';

  bool get requiresResourceBudget =>
      operation.startsWith('llm_') ||
      operation == 'llm_infer' ||
      operation == 'vlm_infer' ||
      operation == 'ocr';
}

class ExecutionPlan {
  const ExecutionPlan({
    required this.taskType,
    required this.stages,
  });

  final String taskType;
  final List<ExecutionPlanStage> stages;
}

class ExecutionPlanProgressEvent {
  const ExecutionPlanProgressEvent({
    required this.stage,
    required this.stageIndex,
    required this.stageCount,
    required this.progressMilli,
  });

  final ExecutionPlanStage stage;
  final int stageIndex;
  final int stageCount;
  final int progressMilli;
}

typedef ExecutionPlanProgressCallback = FutureOr<void> Function(
  ExecutionPlanProgressEvent event,
);

class ExecutionPlanRunContext {
  const ExecutionPlanRunContext({
    this.deviceSnapshot,
    this.safetyController = const RuntimeSafetyController(),
    this.resourceEnforcer,
    this.stageResourceRequest,
    this.reservedResources = const ResourceClassTotals(
      cpuUnits: 0,
      memoryBytes: 0,
      storageBytes: 0,
    ),
    this.safetySignals = RuntimeSafetySignals.none,
    this.heavyTask = true,
    this.onProgress,
  });

  final DeviceSnapshot? deviceSnapshot;
  final RuntimeSafetyController safetyController;
  final WorkerResourceEnforcer? resourceEnforcer;
  final ResourceClassTotals? stageResourceRequest;
  final ResourceClassTotals reservedResources;
  final RuntimeSafetySignals safetySignals;
  final bool heavyTask;
  final ExecutionPlanProgressCallback? onProgress;
}

abstract final class ExecutionPlanCatalog {
  static ExecutionPlan forTaskType(
    String v1Type, {
    bool ocrOnly = false,
  }) {
    if (VisionRuntimeCatalog.isVisionCapability(v1Type)) {
      return _visionPlan(v1Type);
    }

    if (_isSummarizeType(v1Type) && !ocrOnly) {
      return _mapReducePlan(v1Type);
    }

    final stages = <ExecutionPlanStage>[];
    if (TaskTypeMapper.requiresOcr(v1Type)) {
      stages.add(
        ExecutionPlanStage(
          sequence: stages.length + 1,
          name: 'ocr-${v1Type.split('.').first}',
          operation: 'ocr',
          runtimeClass: 'paddle_ocr',
          checkpointEnabled: false,
        ),
      );
    }
    if (TaskTypeMapper.requiresLlm(v1Type, ocrOnly: ocrOnly)) {
      stages.add(
        ExecutionPlanStage(
          sequence: stages.length + 1,
          name: 'llm-${v1Type.split('.').last}',
          operation: 'llm_infer',
          runtimeClass: 'mediapipe_llm',
          checkpointEnabled: false,
        ),
      );
    }
    stages.add(
      ExecutionPlanStage(
        sequence: stages.length + 1,
        name: 'validate',
        operation: 'validate',
        runtimeClass: 'system',
      ),
    );
    stages.add(
      ExecutionPlanStage(
        sequence: stages.length + 1,
        name: 'submit',
        operation: 'submit',
        runtimeClass: 'network_io',
      ),
    );
    return ExecutionPlan(taskType: v1Type, stages: stages);
  }

  static bool _isSummarizeType(String v1Type) =>
      v1Type == TaskTypeMapper.textSummarize ||
      v1Type == TaskTypeMapper.documentSummarize;

  static ExecutionPlan _mapReducePlan(String v1Type) => ExecutionPlan(
        taskType: v1Type,
        stages: const [
          ExecutionPlanStage(
            sequence: 1,
            name: 'chunk',
            operation: 'chunk',
            runtimeClass: 'system',
            checkpointEnabled: true,
          ),
          ExecutionPlanStage(
            sequence: 2,
            name: 'llm-map',
            operation: 'llm_map',
            runtimeClass: 'mediapipe_llm',
            checkpointEnabled: true,
          ),
          ExecutionPlanStage(
            sequence: 3,
            name: 'llm-reduce',
            operation: 'llm_reduce',
            runtimeClass: 'mediapipe_llm',
            checkpointEnabled: true,
          ),
          ExecutionPlanStage(
            sequence: 4,
            name: 'validate',
            operation: 'validate',
            runtimeClass: 'system',
          ),
          ExecutionPlanStage(
            sequence: 5,
            name: 'submit',
            operation: 'submit',
            runtimeClass: 'network_io',
          ),
        ],
      );

  static ExecutionPlan _visionPlan(String v1Type) {
    final kind = VisionRuntimeCatalog.kindFor(v1Type);
    final runtimeClass = VisionRuntimeCatalog.runtimeClassId(kind);
    final inferStage = switch (kind) {
      VisionRuntimeKind.vlm => const ExecutionPlanStage(
          sequence: 1,
          name: 'vlm-analyze',
          operation: 'vlm_infer',
          runtimeClass: 'vlm_runtime',
        ),
      VisionRuntimeKind.segmentation => const ExecutionPlanStage(
          sequence: 1,
          name: 'vision-segment',
          operation: 'vision_segment',
          runtimeClass: 'segmentation_runtime',
        ),
      VisionRuntimeKind.classifier => ExecutionPlanStage(
          sequence: 1,
          name: 'vision-classify-${v1Type.split('.').last}',
          operation: 'vision_classify',
          runtimeClass: runtimeClass,
        ),
    };

    return ExecutionPlan(
      taskType: v1Type,
      stages: [
        inferStage,
        const ExecutionPlanStage(
          sequence: 2,
          name: 'validate',
          operation: 'validate',
          runtimeClass: 'system',
        ),
        const ExecutionPlanStage(
          sequence: 3,
          name: 'submit',
          operation: 'submit',
          runtimeClass: 'network_io',
        ),
      ],
    );
  }

  static bool stageExecutesHandler(
    ExecutionPlanStage stage,
    String v1Type, {
    bool ocrOnly = false,
  }) {
    switch (stage.operation) {
      case 'submit':
      case 'validate':
      case 'chunk':
      case 'llm_reduce':
        return false;
      case 'ocr':
        return TaskTypeMapper.requiresOcr(v1Type) &&
            !TaskTypeMapper.requiresLlm(v1Type, ocrOnly: ocrOnly);
      case 'llm_map':
      case 'llm_infer':
      case 'vlm_infer':
      case 'vision_segment':
      case 'vision_classify':
        return TaskTypeMapper.requiresLlm(v1Type, ocrOnly: ocrOnly) ||
            VisionRuntimeCatalog.isVisionCapability(v1Type);
      default:
        return false;
    }
  }
}

/// Orchestrates plan stages with safety, resource enforcement, and session lifecycle.
class ExecutionPlanRunner {
  ExecutionPlanRunner({
    required ModelRuntimeManager modelRuntime,
    RuntimeSafetyController safetyController = const RuntimeSafetyController(),
    WorkerResourceEnforcer? resourceEnforcer,
    RuntimeExclusiveGroupEnforcer? exclusiveGroupEnforcer,
  })  : _modelRuntime = modelRuntime,
        _defaultSafetyController = safetyController,
        _defaultResourceEnforcer = resourceEnforcer,
        _exclusiveGroupEnforcer = exclusiveGroupEnforcer;

  final ModelRuntimeManager _modelRuntime;
  final RuntimeSafetyController _defaultSafetyController;
  final WorkerResourceEnforcer? _defaultResourceEnforcer;
  final RuntimeExclusiveGroupEnforcer? _exclusiveGroupEnforcer;
  String? _assignmentId;
  int? _fenceToken;

  ModelRuntimeManager get modelRuntime => _modelRuntime;

  String? get boundAssignmentId => _assignmentId;

  int? get boundFenceToken => _fenceToken;

  void enterAssignment(WorkerAssignment assignment) {
    enterAssignmentScope(
      assignmentId: assignment.assignmentId,
      fenceToken: assignment.fenceToken,
    );
  }

  void enterAssignmentScope({
    required String assignmentId,
    required int fenceToken,
  }) {
    if (_assignmentId != null && _assignmentId != assignmentId) {
      _assertSessionsClosed();
      _clearBinding();
    }
    if (_fenceToken != null && _fenceToken != fenceToken) {
      throw StaleFenceException(fenceToken, _fenceToken!);
    }
    _assignmentId = assignmentId;
    _fenceToken = fenceToken;
  }

  Future<T> runStage<T>({
    required ExecutionPlanStage stage,
    required Future<T> Function() body,
  }) {
    _assertBound();
    if (stage.operation == 'ocr') {
      final enforcer = _exclusiveGroupEnforcer;
      if (enforcer != null) {
        return enforcer.withOcrInference(body);
      }
      return body();
    }
    if (!stage.requiresFreshSession) {
      return body();
    }
    return _modelRuntime.withFreshSession(stageId: stage.name, body: body);
  }

  Future<T> runPlan<T>({
    required ExecutionPlan plan,
    required WorkerAssignment assignment,
    required Future<T> Function(ExecutionPlanStage stage) executeStage,
    ExecutionPlanRunContext context = const ExecutionPlanRunContext(),
    bool Function(ExecutionPlanStage stage)? shouldExecuteStage,
  }) {
    return runPlanForScope<T>(
      plan: plan,
      assignmentId: assignment.assignmentId,
      fenceToken: assignment.fenceToken,
      executeStage: executeStage,
      context: context,
      shouldExecuteStage: shouldExecuteStage,
    );
  }

  Future<T> runPlanForScope<T>({
    required ExecutionPlan plan,
    required String assignmentId,
    required int fenceToken,
    required Future<T> Function(ExecutionPlanStage stage) executeStage,
    ExecutionPlanRunContext context = const ExecutionPlanRunContext(),
    bool Function(ExecutionPlanStage stage)? shouldExecuteStage,
  }) async {
    enterAssignmentScope(assignmentId: assignmentId, fenceToken: fenceToken);
    try {
      T? lastResult;
      final stages = plan.stages;
      for (var index = 0; index < stages.length; index++) {
        final stage = stages[index];
        await _guardStage(stage, context);

        final execute = shouldExecuteStage?.call(stage) ??
            ExecutionPlanCatalog.stageExecutesHandler(
              stage,
              plan.taskType,
            );

        if (execute) {
          lastResult = await runStage(
            stage: stage,
            body: () => executeStage(stage),
          );
        }

        await _emitProgress(
          context: context,
          stage: stage,
          stageIndex: index,
          stageCount: stages.length,
        );
      }

      if (lastResult == null) {
        throw StateError(
          'Execution plan for ${plan.taskType} produced no handler result',
        );
      }
      return lastResult;
    } finally {
      exitAssignment();
    }
  }

  void exitAssignment() {
    if (_assignmentId == null) {
      return;
    }
    _assertSessionsClosed();
    _clearBinding();
  }

  Future<void> _guardStage(
    ExecutionPlanStage stage,
    ExecutionPlanRunContext context,
  ) async {
    final snapshot = context.deviceSnapshot;
    final safety = context.safetyController;
    if (snapshot != null) {
      safety.ensureExecuteOrThrow(
        snapshot,
        signals: context.safetySignals,
        heavyTask: context.heavyTask && stage.requiresResourceBudget,
        phase: RuntimeSafetyPhase.duringWork,
      );
    }

    final enforcer = context.resourceEnforcer ?? _defaultResourceEnforcer;
    final request = context.stageResourceRequest;
    if (enforcer != null && request != null && stage.requiresResourceBudget) {
      enforcer.ensureWithinBudgetOrThrow(
        reserved: context.reservedResources,
        requested: request,
      );
    }
  }

  Future<void> _emitProgress({
    required ExecutionPlanRunContext context,
    required ExecutionPlanStage stage,
    required int stageIndex,
    required int stageCount,
  }) async {
    final callback = context.onProgress;
    if (callback == null) {
      return;
    }
    await callback(
      ExecutionPlanProgressEvent(
        stage: stage,
        stageIndex: stageIndex,
        stageCount: stageCount,
        progressMilli: _progressMilli(stageIndex, stageCount),
      ),
    );
  }

  static int _progressMilli(int stageIndex, int stageCount) {
    if (stageCount <= 0) {
      return 1000;
    }
    return (((stageIndex + 1) / stageCount) * 1000).round().clamp(0, 1000);
  }

  void _assertBound() {
    if (_assignmentId == null || _fenceToken == null) {
      throw StateError('ExecutionPlanRunner is not bound to an assignment');
    }
  }

  void _assertSessionsClosed() {
    if (_modelRuntime.openSessionCount != 0) {
      throw StateError(
        'Session leak for assignment $_assignmentId: '
        '${_modelRuntime.openSessionCount} session(s) still open',
      );
    }
  }

  void _clearBinding() {
    _assignmentId = null;
    _fenceToken = null;
  }
}
