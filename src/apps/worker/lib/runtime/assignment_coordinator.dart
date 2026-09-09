import 'dart:convert';
import 'dart:typed_data';

import '../api/worker_api_client.dart';
import '../api/worker_assignment_models.dart';
import '../platform/worker_runtime_channel.dart';
import 'runtime_exclusive_group_enforcer.dart';
import 'assignment_event_reporter.dart';
import 'assignment_inbox.dart';
import 'assignment_receiver.dart';
import 'checkpoint_store.dart';
import 'device_constraints.dart';
import 'execution_stop_tracker.dart';
import 'process_lifecycle_coordinator.dart';
import 'runtime_safety_controller.dart';
import 'privacy_cleanup_coordinator.dart';
import 'storage_pressure_manager.dart';
import 'worker_heartbeat_telemetry.dart';
import 'worker_resource_enforcer.dart';
import 'worker_resource_budget.dart';
import 'device_snapshot.dart';
import 'encrypted_store.dart';
import 'execution_policy.dart';
import 'execution_status.dart';
import 'failure_evidence.dart';
import 'inference_adapter.dart';
import '../telemetry/execution_cost_feedback.dart';
import '../telemetry/worker_task_metrics.dart';
import 'result_signer.dart';
import '../tasks/task_execution_engine.dart';
import '../tasks/task_type_mapper.dart';
import 'runtime_exceptions.dart';
import 'sandbox_limits.dart';

typedef StatusListener = void Function(ExecutionStatus status);

class AssignmentInputBundle {
  const AssignmentInputBundle({
    required this.inputBytes,
    required this.inputDigest,
    required this.modelArtifact,
    this.compareImageBytes,
    this.manifest = const {},
    this.isImageInput = false,
  });

  final Uint8List inputBytes;
  final String inputDigest;
  final ModelArtifact modelArtifact;
  final Uint8List? compareImageBytes;
  final Map<String, dynamic> manifest;
  final bool isImageInput;
}

typedef InputLoader = Future<AssignmentInputBundle> Function(WorkerAssignment assignment);

class AssignmentCoordinator {
  AssignmentCoordinator({
    required WorkerApiClient api,
    required EncryptedStore store,
    required WorkerRuntimeChannel platform,
    required InferenceAdapter inference,
    DeviceConstraints? constraints,
    RuntimeSafetyController? safetyController,
    WorkerResourceEnforcer? resourceEnforcer,
    SandboxLimits? sandbox,
    InputLoader? inputLoader,
    TaskExecutionEngine? taskEngine,
    String? accessToken,
    StatusListener? onStatus,
    AssignmentReceiver? assignmentReceiver,
    StoragePressureManager? storagePressure,
    AssignmentInbox? assignmentInbox,
    ProcessLifecycleCoordinator? processLifecycle,
    PrivacyCleanupCoordinator? privacyCleanup,
  })  : _api = api,
        _checkpointStore = CheckpointStore(store),
        _platform = platform,
        _inference = inference,
        _constraints = constraints ?? const DeviceConstraints(),
        _safety = safetyController ?? const RuntimeSafetyController(),
        _resourceEnforcer = resourceEnforcer,
        _sandbox = sandbox ?? const SandboxLimits(),
        _inputLoader = inputLoader ?? _defaultInputLoader,
        _taskEngine = taskEngine,
        _accessToken = accessToken ?? 'token',
        _onStatus = onStatus,
        _receiver = assignmentReceiver ?? AssignmentReceiver(),
        _storagePressure = storagePressure ?? StoragePressureManager(),
        _assignmentInbox = assignmentInbox ?? AssignmentInbox(store: store),
        _processLifecycle = processLifecycle,
        _privacyCleanup = privacyCleanup ?? PrivacyCleanupCoordinator();

  final WorkerApiClient _api;
  final CheckpointStore _checkpointStore;
  final WorkerRuntimeChannel _platform;
  final InferenceAdapter _inference;
  final DeviceConstraints _constraints;
  final RuntimeSafetyController _safety;
  final WorkerResourceEnforcer? _resourceEnforcer;
  final SandboxLimits _sandbox;
  final InputLoader _inputLoader;
  final TaskExecutionEngine? _taskEngine;
  final String _accessToken;
  final StatusListener? _onStatus;
  final AssignmentReceiver _receiver;
  final StoragePressureManager _storagePressure;
  final AssignmentInbox _assignmentInbox;
  final ProcessLifecycleCoordinator? _processLifecycle;
  final PrivacyCleanupCoordinator _privacyCleanup;
  final FailureEvidenceMapper _failureMapper = const FailureEvidenceMapper();
  final ExecutionStopTracker _stopTracker = ExecutionStopTracker();
  bool _assignmentStarted = false;
  WorkerResourceReservationEntry? _activeReservation;

  ExecutionStatus _status = const ExecutionStatus(phase: ExecutionPhase.idle);
  bool _cancelRequested = false;

  ExecutionStatus get status => _status;

  void _emit(ExecutionStatus next) {
    _status = next;
    _onStatus?.call(next);
  }

  Future<WorkerAssignment?> pollAssignment({
    DeviceSnapshot? snapshot,
    RuntimeSafetySignals? safetySignals,
    int waitSeconds = 0,
  }) async {
    _emit(_status.copyWith(phase: ExecutionPhase.waitingForAssignment));
    final device = snapshot ?? await _platform.readDeviceSnapshot();
    _constraints.ensureOrThrow(device);
    _safety.ensureExecuteOrThrow(device, signals: safetySignals ?? RuntimeSafetySignals.none);
    return _api.getNextAssignment(accessToken: _accessToken, waitSeconds: waitSeconds);
  }

  Future<void> reconcileInboxBootstrap() async {
    final bootstrap = await _api.getAssignmentInboxBootstrap(accessToken: _accessToken);
    final deliveries = bootstrap['deliveries'] as List<dynamic>? ?? const [];
    final serverEntries = deliveries.map((item) {
      final map = item as Map<String, dynamic>;
      return AssignmentInboxEntry(
        assignmentId: map['assignmentId'] as String,
        attemptId: map['assignmentId'] as String,
        fenceToken: map['fenceToken'] as int,
        recordedAt: DateTime.now().toUtc(),
        deliveryInboxId: map['deliveryInboxId'] as String?,
        ackedAt: (map['acked'] as bool? ?? false) ? DateTime.now().toUtc() : null,
      );
    });
    await _assignmentInbox.reconcileBootstrap(serverEntries: serverEntries);
  }

  Future<WorkerAssignment?> acceptPolledAssignment(WorkerAssignment assignment) async {
    await reconcileInboxBootstrap();
    final receipt = await _assignmentInbox.recordBeforeProcess(
      assignment,
      deliveryInboxId: assignment.deliveryInboxId,
    );
    if (receipt.disposition == AssignmentInboxDisposition.staleFenceSuperseded) {
      throw AssignmentRejectedException(
        AssignmentValidationIssue(
          step: AssignmentValidationStep.fence,
          failureCode: 'ASSIGNMENT_STALE_FENCE',
          retryable: false,
          detail: 'local inbox has newer fence ${receipt.entry.fenceToken}',
        ),
      );
    }
    if (receipt.disposition == AssignmentInboxDisposition.duplicateReplay) {
      return null;
    }
    return assignment;
  }

  Future<ResumeDecision> inspectResume(WorkerAssignment assignment, AssignmentInputBundle bundle) async {
    if (_processLifecycle?.requiresFreshGrantReconciliation ?? false) {
      return const ResumeDecision(
        startFresh: true,
        discardedStaleCheckpoint: true,
        blockedPendingFreshGrant: true,
      );
    }
    final checkpoint = await _checkpointStore.latestFor(assignment.assignmentId);
    if (checkpoint == null) {
      return const ResumeDecision(startFresh: true);
    }
    if (!checkpoint.canResume(
      activeFenceToken: assignment.fenceToken,
      activeModelDigest: bundle.modelArtifact.digestSha256,
      activeInputDigest: bundle.inputDigest,
    )) {
      await _checkpointStore.purge(assignment.assignmentId);
      return const ResumeDecision(startFresh: true, discardedStaleCheckpoint: true);
    }
    final state = await _checkpointStore.readState(checkpoint);
    return ResumeDecision(startFresh: false, checkpoint: checkpoint, resumedState: state);
  }

  Future<void> executeAssignment(
    WorkerAssignment assignment, {
    DeviceSnapshot? snapshot,
    RuntimeSafetySignals? safetySignals,
    ResourceClassTotals? taskResourceRequest,
    ResumeDecision? resume,
  }) async {
    _cancelRequested = false;
    _assignmentStarted = false;
    final startedAt = DateTime.now();
    try {
      await _executeAssignmentBody(
        assignment,
        startedAt: startedAt,
        snapshot: snapshot,
        safetySignals: safetySignals,
        taskResourceRequest: taskResourceRequest,
        resume: resume,
      );
    } catch (error) {
      await _submitFailureEvidence(
        assignment: assignment,
        error: error,
        startedAt: startedAt,
      );
      rethrow;
    }
  }

  Future<void> _executeAssignmentBody(
    WorkerAssignment assignment, {
    required DateTime startedAt,
    DeviceSnapshot? snapshot,
    RuntimeSafetySignals? safetySignals,
    ResourceClassTotals? taskResourceRequest,
    ResumeDecision? resume,
  }) async {
    final device = snapshot ?? await _platform.readDeviceSnapshot();
    _receiver.ensureAccepted(_receiver.validateContract(assignment));
    _processLifecycle?.acknowledgeFreshGrantReconciliation();
    await _assignmentInbox.recordBeforeProcess(
      assignment,
      deliveryInboxId: assignment.deliveryInboxId,
    );
    _receiver.ensureAccepted(_receiver.validateConsent(device));
    _storagePressure.ensureHeadroomForWork(device);
    _constraints.ensureOrThrow(device, heavyTask: true);
    _safety.ensureExecuteOrThrow(
      device,
      signals: safetySignals ?? RuntimeSafetySignals.none,
      heavyTask: true,
    );

    if (_resourceEnforcer != null && taskResourceRequest != null) {
      _resourceEnforcer!.ensureWithinBudgetOrThrow(
        reserved: const ResourceClassTotals(cpuUnits: 0, memoryBytes: 0, storageBytes: 0),
        requested: taskResourceRequest,
      );
    }

    _emit(ExecutionStatus(
      phase: ExecutionPhase.preparing,
      assignmentId: assignment.assignmentId,
      taskId: assignment.taskId,
      taskType: assignment.taskType,
    ));
    await _platform.startForegroundService(
      assignmentId: assignment.assignmentId,
      taskType: assignment.taskType,
    );

    final bundle = await _inputLoader(assignment);
    final feedbackBuilder = ExecutionCostFeedbackBuilder(
      taskType: assignment.taskType,
      inputBytes: bundle.inputBytes.length,
      startSnapshot: device,
    );
    final decision = resume ?? await inspectResume(assignment, bundle);
    _receiver.ensureAccepted(
      _receiver.validateFence(
        assignment: assignment,
        checkpointFenceToken: decision.checkpoint?.fenceToken,
      ),
    );

    final signingMaterial = await _platform.signingMaterial();
    final usePipeline =
        _taskEngine != null && TaskTypeMapper.isPipelineTask(assignment.taskType);
    if (!usePipeline) {
      await _inference.loadVerified(bundle.modelArtifact, signingKey: signingMaterial);
    }

    await _api.reportAssignmentStarted(
      assignmentId: assignment.assignmentId,
      accessToken: _accessToken,
      leaseToken: assignment.leaseToken,
      fenceToken: assignment.fenceToken,
      idempotencyKey: 'start-${assignment.attemptId}',
    );
    await _assignmentInbox.markAcked(assignment.assignmentId, fenceToken: assignment.fenceToken);
    _assignmentStarted = true;
    _activeReservation = WorkerHeartbeatTelemetry.reservationForTask(
      assignmentId: assignment.assignmentId,
      taskType: assignment.taskType,
    );
    final checkpoint = await _checkpointStore.latestFor(assignment.assignmentId);
    _storagePressure.bindActiveAssignment(
      assignmentId: assignment.assignmentId,
      fenceToken: assignment.fenceToken,
      protectedModelIds: {
        assignment.modelVersionId,
        bundle.modelArtifact.modelVersionId,
      },
      protectedBlobRefs: {
        if (checkpoint != null) checkpoint.encryptedBlobRef,
        if (decision.checkpoint != null) decision.checkpoint!.encryptedBlobRef,
      },
    );

    _privacyCleanup.bindActiveBuffers(assignmentId: assignment.assignmentId);
    _privacyCleanup.registerTempBlob(
      assignmentId: assignment.assignmentId,
      blobRef: 'runtime/decode/${assignment.assignmentId}',
    );
    _emit(_status.copyWith(phase: ExecutionPhase.running, progressMilli: decision.checkpoint?.progressMilli ?? 0));

    var lastReportedProgress = decision.checkpoint?.progressMilli ?? 0;
    Future<void> onProgressWrapper(int progressMilli) async {
      if (_cancelRequested) {
        throw const LeaseRevokedException();
      }
      final current = await _platform.readDeviceSnapshot();
      final constraint = _constraints.evaluate(current, heavyTask: true);
      if (!constraint.allowed) {
        throw ConstraintBlockedException(constraint.violation!, constraint.detail);
      }
      final safety = _safety.evaluate(
        current,
        signals: safetySignals ?? RuntimeSafetySignals.none,
        heavyTask: true,
        phase: RuntimeSafetyPhase.duringWork,
      );
      if (!safety.mayExecute) {
        throw RuntimeSafetyException(safety);
      }
      if (!_sandbox.withinDuration(DateTime.now().difference(startedAt))) {
        throw StateError('Execution exceeded sandbox time limit');
      }
      _emit(_status.copyWith(progressMilli: progressMilli));
      await _platform.updateForegroundStatus(progressMilli: progressMilli, detail: assignment.taskType);
      if (progressMilli - lastReportedProgress >= ExecutionPolicy.minimumProgressDeltaMilli) {
        await _api.progressAssignment(
          assignmentId: assignment.assignmentId,
          accessToken: _accessToken,
          idempotencyKey: 'progress-${assignment.attemptId}-$progressMilli',
          body: {
            'leaseToken': assignment.leaseToken,
            'fenceToken': assignment.fenceToken,
            'sequence': progressMilli,
            'stage': usePipeline ? 'pipeline' : 'infer',
            'progressBps': progressMilli * 10,
          },
        );
        lastReportedProgress = progressMilli;
        await _writeCheckpoint(
          assignment: assignment,
          bundle: bundle,
          progressMilli: progressMilli,
          runtimeState: Uint8List.fromList([progressMilli]),
        );
      }
    }
    final InferenceOutput output;
    if (usePipeline) {
      final eventReporter = AssignmentEventReporter(
        api: _api,
        assignment: assignment,
        accessToken: _accessToken,
        inputSha256: bundle.inputDigest,
      );
      output = await _taskEngine!.execute(
        context: TaskExecutionContext(
          assignment: assignment,
          manifest: bundle.manifest,
          inputBytes: bundle.inputBytes,
          compareImageBytes: bundle.compareImageBytes,
          isImageInput: bundle.isImageInput,
        ),
        signingKey: signingMaterial,
        freeStorageMb: device.freeStorageMb,
        isCancelled: () => _cancelRequested,
        eventReporter: eventReporter,
      );
      await onProgressWrapper(1000);
    } else {
      output = await _inference.run(
        inputBytes: bundle.inputBytes,
        resumedState: decision.resumedState,
        onProgress: onProgressWrapper,
      );
    }

    _emit(_status.copyWith(phase: ExecutionPhase.submitting, progressMilli: output.progressMilli));
    final resultSha256 = sha256Hex(output.resultBytes);
    final outputArtifactId = 'art_${assignment.attemptId}';
    // The result MAC is scoped to this short-lived lease capability. The server
    // can verify it without persisting a device private secret.
    final signer = ResultSigner(signingMaterial: assignment.leaseToken);
    final signature = signer.sign(
      assignmentId: assignment.assignmentId,
      fenceToken: assignment.fenceToken,
      resultSha256: resultSha256,
      outputArtifactId: outputArtifactId,
    );

    final endSnapshot = await _platform.readDeviceSnapshot();
    final taskMetrics = _taskMetricsFromOutput(output.metrics, startedAt: startedAt)
      ..inputBytes ??= bundle.inputBytes.length;
    final costFeedback = feedbackBuilder.build(
      metrics: taskMetrics,
      endSnapshot: endSnapshot,
    );
    final completionMetrics = Map<String, dynamic>.from(output.metrics)
      ..['costFeedback'] = costFeedback.toJson();

    await _api.completeAssignment(
      assignmentId: assignment.assignmentId,
      accessToken: _accessToken,
      idempotencyKey: 'complete-${assignment.attemptId}',
      body: {
        'leaseToken': assignment.leaseToken,
        'fenceToken': assignment.fenceToken,
        'resultSha256': resultSha256,
        'outputArtifactId': outputArtifactId,
        'outputInline': utf8.decode(output.resultBytes),
        'metrics': completionMetrics,
        'signature': signature,
      },
    );

    await _cleanup(assignment);
    await _platform.stopForegroundService();
    final outputKind = output.metrics['outputKind'];
    final structured = output.metrics['structuredResult'];
    final resultPreview = outputKind == 'json' && structured is Map
        ? (structured['output']?['rawText'] as String? ??
            structured['output']?['data']?.toString() ??
            structured['error']?['message'] as String? ??
            'Structured task result ready')
        : outputKind == 'image'
            ? (output.metrics['resultSummary'] as String? ?? 'Image output ready')
            : utf8.decode(output.resultBytes);
    _emit(_status.copyWith(
      phase: ExecutionPhase.completed,
      progressMilli: 1000,
      detail: resultPreview,
      taskType: assignment.taskType,
      assignmentId: assignment.assignmentId,
      taskId: assignment.taskId,
    ));
  }

  Future<void> safeStopAndCheckpoint(
    WorkerAssignment assignment,
    AssignmentInputBundle bundle,
    int progressMilli,
  ) async {
    _emit(_status.copyWith(phase: ExecutionPhase.checkpointing, progressMilli: progressMilli));
    await _writeCheckpoint(
      assignment: assignment,
      bundle: bundle,
      progressMilli: progressMilli,
      runtimeState: Uint8List.fromList([progressMilli]),
    );
    _emit(_status.copyWith(phase: ExecutionPhase.paused));
  }

  Future<void> _submitFailureEvidence({
    required WorkerAssignment assignment,
    required Object error,
    required DateTime startedAt,
  }) async {
    final checkpoint = await _checkpointStore.latestFor(assignment.assignmentId);
    final evidence = _failureMapper.map(
      assignment: assignment,
      error: error,
      executionTime: DateTime.now().difference(startedAt),
      checkpointId: checkpoint?.encryptedBlobRef,
    );
    if (evidence == null) {
      return;
    }
    try {
      await _api.failAssignment(
        assignmentId: assignment.assignmentId,
        accessToken: _accessToken,
        idempotencyKey: 'fail-${assignment.attemptId}-${evidence.failureCode}',
        body: evidence.toFailRequest(leaseToken: assignment.leaseToken),
      );
    } finally {
      _storagePressure.clearActiveAssignment();
      if (_assignmentStarted) {
        await _cleanup(assignment, preserveCheckpoint: checkpoint != null);
        await _platform.stopForegroundService();
      }
      _emit(_status.copyWith(
        phase: ExecutionPhase.failed,
        detail: evidence.failureCode,
        assignmentId: assignment.assignmentId,
        taskId: assignment.taskId,
        taskType: assignment.taskType,
      ));
    }
  }

  Future<void> abandon(WorkerAssignment assignment, {required String reason}) async {
    await _api.abandonAssignment(
      assignmentId: assignment.assignmentId,
      accessToken: _accessToken,
      leaseToken: assignment.leaseToken,
      fenceToken: assignment.fenceToken,
      reason: reason,
      idempotencyKey: 'abandon-${assignment.attemptId}',
    );
    await _cleanup(assignment);
    await _platform.stopForegroundService();
    _emit(_status.copyWith(phase: ExecutionPhase.failed, detail: reason));
  }

  void requestCancel() => _cancelRequested = true;

  Future<void> _writeCheckpoint({
    required WorkerAssignment assignment,
    required AssignmentInputBundle bundle,
    required int progressMilli,
    required Uint8List runtimeState,
  }) async {
    final encrypted = await _platform.encryptLocal(runtimeState);
    final ref = blobRef(assignment.assignmentId, progressMilli);
    final record = CheckpointRecord(
      assignmentId: assignment.assignmentId,
      attemptId: assignment.attemptId,
      fenceToken: assignment.fenceToken,
      modelVersionId: assignment.modelVersionId,
      modelDigest: bundle.modelArtifact.digestSha256,
      inputDigest: bundle.inputDigest,
      sequence: progressMilli,
      progressMilli: progressMilli,
      runtimeStateDigest: sha256Hex(runtimeState),
      encryptedBlobRef: ref,
      savedAt: DateTime.now(),
    );
    await _checkpointStore.save(record, encrypted);
    await _api.checkpointAssignment(
      assignmentId: assignment.assignmentId,
      accessToken: _accessToken,
      idempotencyKey: 'checkpoint-${assignment.attemptId}-$progressMilli',
      body: {
        'leaseToken': assignment.leaseToken,
        'fenceToken': assignment.fenceToken,
        'sequence': progressMilli,
        'modelVersionId': assignment.modelVersionId,
        'inputSha256': bundle.inputDigest,
        'checkpointSha256': record.runtimeStateDigest,
        'encryptedBlobRef': ref,
      },
    );
  }

  Future<void> _cleanup(WorkerAssignment assignment, {bool preserveCheckpoint = false}) async {
    _emit(_status.copyWith(phase: ExecutionPhase.cleaningUp));
    _stopTracker.requestStop(reason: 'assignment_cleanup');
    _activeReservation = null;
    _storagePressure.clearActiveAssignment();
    await _privacyCleanup.cleanupAfterAssignment(
      assignmentId: assignment.assignmentId,
      checkpointStore: _checkpointStore,
      preserveCheckpoint: preserveCheckpoint,
    );
    final proof = buildPhysicalReleaseProof(
      assignmentId: assignment.assignmentId,
      fenceToken: assignment.fenceToken,
      cleanupPhase: 'cleanup',
    );
    _stopTracker.confirmStop(proof: proof);
    try {
      await _api.confirmPhysicalStop(
        assignmentId: assignment.assignmentId,
        accessToken: _accessToken,
        leaseToken: assignment.leaseToken,
        fenceToken: assignment.fenceToken,
        proof: proof,
        idempotencyKey: 'confirm-stop-${assignment.attemptId}',
      );
    } catch (_) {
      // Server may already have logically released; local stop confirmation still recorded.
    } finally {
      _stopTracker.reset();
    }
  }

  List<String> activeAssignmentIds() {
    final assignmentId = _status.assignmentId;
    if (assignmentId == null) {
      return const [];
    }
    return switch (_status.phase) {
      ExecutionPhase.idle ||
      ExecutionPhase.waitingForAssignment ||
      ExecutionPhase.completed ||
      ExecutionPhase.failed =>
        const [],
      _ => [assignmentId],
    };
  }

  WorkerHeartbeatTelemetryContext heartbeatTelemetryContext({
    required DeviceSnapshot snapshot,
    required int sequence,
    RuntimeExclusiveGroupEnforcer? runtimeExclusiveGroups,
    List<Map<String, String>> installedModels = const [],
    List<String> loadedModelIds = const [],
    int cpuUsageBps = 0,
    WorkerCalibrationView? calibrationView,
    String contributionModeId = 'balanced',
    Map<String, dynamic>? identityLifecycleView,
  }) {
    return WorkerHeartbeatTelemetryContext(
      sequence: sequence,
      snapshot: snapshot,
      currentLeases: activeAssignmentIds(),
      installedModels: installedModels,
      loadedModelIds: loadedModelIds,
      cpuUsageBps: cpuUsageBps,
      runtimeExclusiveGroups: runtimeExclusiveGroups,
      calibrationView: calibrationView,
      activeReservation: _activeReservation,
      contributionModeId: contributionModeId,
      identityLifecycleView: identityLifecycleView,
    );
  }

  WorkerTaskMetrics _taskMetricsFromOutput(
    Map<String, dynamic> metrics, {
    required DateTime startedAt,
  }) {
    final taskMetrics = WorkerTaskMetrics(startedAt: startedAt);
    taskMetrics.queueMs = metrics['queueMs'] as int? ?? 0;
    taskMetrics.preprocessMs = metrics['preprocessMs'] as int? ?? 0;
    taskMetrics.ocrMs = metrics['ocrMs'] as int? ?? 0;
    taskMetrics.llmMs = metrics['llmMs'] as int? ?? 0;
    taskMetrics.inputBytes = metrics['inputBytes'] as int?;
    taskMetrics.peakMemoryMb = metrics['peakMemoryMb'] as int?;
    return taskMetrics;
  }

  static Future<AssignmentInputBundle> _defaultInputLoader(WorkerAssignment assignment) async {
    final inputBytes = Uint8List.fromList('input-for-${assignment.taskType}'.codeUnits);
    final modelBytes = Uint8List.fromList('model'.codeUnits);
    final modelDigest = sha256Hex(modelBytes);
    final signingKey = 'test-signing-material';
    return AssignmentInputBundle(
      inputBytes: inputBytes,
      inputDigest: sha256Hex(inputBytes),
      modelArtifact: ModelArtifact(
        modelVersionId: assignment.modelVersionId,
        digestSha256: modelDigest,
        signatureSha256: sha256HexString('$modelDigest:$signingKey'),
        backend: InferenceBackend.stub,
        bytes: modelBytes,
      ),
    );
  }
}

class ResumeDecision {
  const ResumeDecision({
    required this.startFresh,
    this.checkpoint,
    this.resumedState,
    this.discardedStaleCheckpoint = false,
    this.blockedPendingFreshGrant = false,
  });

  final bool startFresh;
  final CheckpointRecord? checkpoint;
  final Uint8List? resumedState;
  final bool discardedStaleCheckpoint;
  final bool blockedPendingFreshGrant;
}
