import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../api/worker_api_client.dart';
import '../api/worker_assignment_models.dart';
import '../contracts/worker_error.dart';
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
import 'result_submission_outbox.dart';
import '../tasks/task_execution_engine.dart';
import '../tasks/task_type_mapper.dart';
import 'runtime_exceptions.dart';
import 'sandbox_limits.dart';
import 'worker_access_token_provider.dart';

typedef StatusListener = void Function(ExecutionStatus status);
typedef RuntimeLog = void Function(String message);

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

typedef InputLoader =
    Future<AssignmentInputBundle> Function(WorkerAssignment assignment);

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
    WorkerAccessTokenProvider? accessTokenProvider,
    StatusListener? onStatus,
    RuntimeLog? onLog,
    AssignmentReceiver? assignmentReceiver,
    StoragePressureManager? storagePressure,
    AssignmentInbox? assignmentInbox,
    ProcessLifecycleCoordinator? processLifecycle,
    PrivacyCleanupCoordinator? privacyCleanup,
  }) : _api = api,
       _checkpointStore = CheckpointStore(store),
       _resultOutbox = ResultSubmissionOutbox(store: store),
       _platform = platform,
       _inference = inference,
       _constraints = constraints ?? const DeviceConstraints(),
       _safety = safetyController ?? const RuntimeSafetyController(),
       _resourceEnforcer = resourceEnforcer,
       _sandbox = sandbox ?? const SandboxLimits(),
       _inputLoader = inputLoader ?? _defaultInputLoader,
       _taskEngine = taskEngine,
       _accessTokens =
           accessTokenProvider ??
           WorkerAccessTokenProvider(
             initialToken: accessToken ?? (kDebugMode ? 'token' : ''),
           ),
       _onStatus = onStatus,
       _onLog = onLog,
       _receiver = assignmentReceiver ?? AssignmentReceiver(),
       _storagePressure = storagePressure ?? StoragePressureManager(),
       _assignmentInbox = assignmentInbox ?? AssignmentInbox(store: store),
       _processLifecycle = processLifecycle,
       _privacyCleanup = privacyCleanup ?? PrivacyCleanupCoordinator();

  final WorkerApiClient _api;
  final CheckpointStore _checkpointStore;
  final ResultSubmissionOutbox _resultOutbox;
  final WorkerRuntimeChannel _platform;
  final InferenceAdapter _inference;
  final DeviceConstraints _constraints;
  final RuntimeSafetyController _safety;
  final WorkerResourceEnforcer? _resourceEnforcer;
  final SandboxLimits _sandbox;
  final InputLoader _inputLoader;
  final TaskExecutionEngine? _taskEngine;
  final WorkerAccessTokenProvider _accessTokens;

  String get _accessToken => _accessTokens.requireToken();
  final StatusListener? _onStatus;
  final RuntimeLog? _onLog;
  final AssignmentReceiver _receiver;
  final StoragePressureManager _storagePressure;
  final AssignmentInbox _assignmentInbox;
  final ProcessLifecycleCoordinator? _processLifecycle;
  final PrivacyCleanupCoordinator _privacyCleanup;
  final FailureEvidenceMapper _failureMapper = const FailureEvidenceMapper();
  final ExecutionStopTracker _stopTracker = ExecutionStopTracker();
  bool _assignmentStarted = false;
  WorkerResourceReservationEntry? _activeReservation;
  Timer? _leaseRenewalTimer;
  int _leaseRenewSequence = 0;

  ExecutionStatus _status = const ExecutionStatus(phase: ExecutionPhase.idle);
  bool _cancelRequested = false;

  ExecutionStatus get status => _status;

  void _emit(ExecutionStatus next) {
    _status = next;
    _onStatus?.call(next);
  }

  void _log(String message) {
    _onLog?.call(message);
  }

  Future<WorkerAssignment?> pollAssignment({
    DeviceSnapshot? snapshot,
    RuntimeSafetySignals? safetySignals,
    int waitSeconds = 0,
  }) async {
    _emit(_status.copyWith(phase: ExecutionPhase.waitingForAssignment));
    final device = snapshot ?? await _platform.readDeviceSnapshot();
    _constraints.ensureOrThrow(device);
    _safety.ensureExecuteOrThrow(
      device,
      signals: safetySignals ?? RuntimeSafetySignals.none,
    );
    return _api.getNextAssignment(
      accessToken: _accessToken,
      waitSeconds: waitSeconds,
    );
  }

  Future<void> reconcileInboxBootstrap() async {
    final bootstrap = await _api.getAssignmentInboxBootstrap(
      accessToken: _accessToken,
    );
    final deliveries = bootstrap['deliveries'] as List<dynamic>? ?? const [];
    final serverEntries = deliveries.map((item) {
      final map = item as Map<String, dynamic>;
      return AssignmentInboxEntry(
        assignmentId: map['assignmentId'] as String,
        attemptId: map['attemptId'] as String? ?? map['assignmentId'] as String,
        fenceToken: map['fenceToken'] as int,
        recordedAt: DateTime.now().toUtc(),
        deliveryInboxId: map['deliveryInboxId'] as String?,
        ackedAt: (map['acked'] as bool? ?? false)
            ? DateTime.now().toUtc()
            : null,
      );
    });
    await _assignmentInbox.reconcileBootstrap(serverEntries: serverEntries);
  }

  Future<WorkerAssignment?> acceptPolledAssignment(
    WorkerAssignment assignment,
  ) async {
    final localBeforeBootstrap = await _assignmentInbox.latestEntryFor(
      assignment.assignmentId,
    );
    await reconcileInboxBootstrap();
    final latest = await _assignmentInbox.latestEntryFor(
      assignment.assignmentId,
    );
    if (latest != null && latest.fenceToken > assignment.fenceToken) {
      throw AssignmentRejectedException(
        AssignmentValidationIssue(
          step: AssignmentValidationStep.fence,
          failureCode: 'ASSIGNMENT_STALE_FENCE',
          retryable: false,
          detail: 'local inbox has newer fence ${latest.fenceToken}',
        ),
      );
    }
    if (localBeforeBootstrap?.fenceToken == assignment.fenceToken) {
      return null;
    }
    // executeAssignment performs the one durable inbox write immediately
    // before validation and execution side effects.
    return assignment;
  }

  Future<ResumeDecision> inspectResume(
    WorkerAssignment assignment,
    AssignmentInputBundle bundle,
  ) async {
    if (_processLifecycle?.requiresFreshGrantReconciliation ?? false) {
      return const ResumeDecision(
        startFresh: true,
        discardedStaleCheckpoint: true,
        blockedPendingFreshGrant: true,
      );
    }
    final checkpoint = await _checkpointStore.latestFor(
      assignment.assignmentId,
    );
    if (checkpoint == null) {
      return const ResumeDecision(startFresh: true);
    }
    if (!checkpoint.canResume(
      activeFenceToken: assignment.fenceToken,
      activeModelDigest: bundle.modelArtifact.digestSha256,
      activeInputDigest: bundle.inputDigest,
    )) {
      await _checkpointStore.purge(assignment.assignmentId);
      return const ResumeDecision(
        startFresh: true,
        discardedStaleCheckpoint: true,
      );
    }
    final state = await _checkpointStore.readState(checkpoint);
    return ResumeDecision(
      startFresh: false,
      checkpoint: checkpoint,
      resumedState: state,
    );
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
    final now = DateTime.now().toUtc();
    _log(
      '[VALIDATE CONTRACT] assignmentId=${assignment.assignmentId} '
      'now=${now.toIso8601String()} '
      'startDeadlineAt=${assignment.startDeadlineAt.toUtc().toIso8601String()} '
      'leaseExpiresAt=${assignment.leaseExpiresAt.toUtc().toIso8601String()}',
    );
    final contractVerdict = _receiver.validateContract(assignment);
    if (!contractVerdict.accepted) {
      _log(
        '[VALIDATE CONTRACT REJECTED] '
        'code=${contractVerdict.issue?.failureCode} '
        'detail=${contractVerdict.issue?.detail}',
      );
    } else {
      _log('[VALIDATE CONTRACT OK] assignmentId=${assignment.assignmentId}');
    }
    _receiver.ensureAccepted(contractVerdict);
    _processLifecycle?.acknowledgeFreshGrantReconciliation();
    final inboxReceipt = await _assignmentInbox.recordBeforeProcess(
      assignment,
      deliveryInboxId: assignment.deliveryInboxId,
    );
    if (inboxReceipt.disposition ==
        AssignmentInboxDisposition.duplicateReplay) {
      return;
    }
    if (inboxReceipt.disposition ==
        AssignmentInboxDisposition.staleFenceSuperseded) {
      throw AssignmentRejectedException(
        AssignmentValidationIssue(
          step: AssignmentValidationStep.fence,
          failureCode: 'ASSIGNMENT_STALE_FENCE',
          retryable: false,
          detail:
              'local inbox has newer fence ${inboxReceipt.entry.fenceToken}',
        ),
      );
    }
    final consentVerdict = _receiver.validateConsent(device);
    _receiver.ensureAccepted(consentVerdict);
    _log('[VALIDATE CONSENT OK] assignmentId=${assignment.assignmentId}');
    _storagePressure.ensureHeadroomForWork(device);
    _constraints.ensureOrThrow(device, heavyTask: true);
    _safety.ensureExecuteOrThrow(
      device,
      signals: safetySignals ?? RuntimeSafetySignals.none,
      heavyTask: true,
    );

    if (_resourceEnforcer != null && taskResourceRequest != null) {
      _resourceEnforcer!.ensureWithinBudgetOrThrow(
        reserved: const ResourceClassTotals(
          cpuUnits: 0,
          memoryBytes: 0,
          storageBytes: 0,
        ),
        requested: taskResourceRequest,
      );
    }

    _emit(
      ExecutionStatus(
        phase: ExecutionPhase.preparing,
        assignmentId: assignment.assignmentId,
        taskId: assignment.taskId,
        taskType: assignment.taskType,
      ),
    );
    await _platform.startForegroundService(
      assignmentId: assignment.assignmentId,
      taskType: assignment.taskType,
    );

    _log('[INPUT REQUEST] loading assignment manifest and payload');
    final bundle = await _inputLoader(assignment);
    _log(
      '[INPUT RESPONSE] bytes=${bundle.inputBytes.length} '
      'digest=${bundle.inputDigest} image=${bundle.isImageInput}',
    );
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
        _taskEngine != null &&
        TaskTypeMapper.isPipelineTask(assignment.taskType);
    if (!usePipeline) {
      _log('[MODEL LOAD] verifying and loading ${assignment.modelVersionId}');
      await _inference.loadVerified(
        bundle.modelArtifact,
        signingKey: signingMaterial,
      );
      _log('[MODEL LOAD OK] ${assignment.modelVersionId}');
    }

    _log('[START REQUEST] assignmentId=${assignment.assignmentId}');
    await _api.reportAssignmentStarted(
      assignmentId: assignment.assignmentId,
      accessToken: _accessToken,
      leaseToken: assignment.leaseToken,
      fenceToken: assignment.fenceToken,
      idempotencyKey: 'start-${assignment.attemptId}',
    );
    _log('[START RESPONSE] assignment accepted by worker-gateway');
    await _assignmentInbox.markAcked(
      assignment.assignmentId,
      fenceToken: assignment.fenceToken,
    );
    _assignmentStarted = true;
    _startLeaseRenewal(assignment);
    _activeReservation = WorkerHeartbeatTelemetry.reservationForTask(
      assignmentId: assignment.assignmentId,
      taskType: assignment.taskType,
    );
    final checkpoint = await _checkpointStore.latestFor(
      assignment.assignmentId,
    );
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
    _emit(
      _status.copyWith(
        phase: ExecutionPhase.running,
        progressMilli: decision.checkpoint?.progressMilli ?? 0,
      ),
    );

    var lastReportedProgress = decision.checkpoint?.progressMilli ?? 0;
    Future<void> onProgressWrapper(int progressMilli) async {
      if (_cancelRequested) {
        throw const LeaseRevokedException();
      }
      final current = await _platform.readDeviceSnapshot();
      final constraint = _constraints.evaluate(current, heavyTask: true);
      if (!constraint.allowed) {
        throw ConstraintBlockedException(
          constraint.violation!,
          constraint.detail,
        );
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
      await _platform.updateForegroundStatus(
        progressMilli: progressMilli,
        detail: assignment.taskType,
      );
      if (progressMilli - lastReportedProgress >=
          ExecutionPolicy.minimumProgressDeltaMilli) {
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
    _log(
      '[INFERENCE ROUTE] ${usePipeline ? "task-pipeline" : "direct-model"} '
      'taskType=${assignment.taskType}',
    );
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
    _log(
      '[INFERENCE OUTPUT] bytes=${output.resultBytes.length} '
      'progress=${output.progressMilli} metrics=${jsonEncode(output.metrics)}',
    );
    final taskStatus = output.metrics['taskStatus'] as String?;
    if (taskStatus != null && taskStatus != WorkerResultStatus.succeeded.name) {
      final structured = output.metrics['structuredResult'];
      final errorMap = structured is Map<String, dynamic>
          ? structured['error'] as Map<String, dynamic>?
          : null;
      throw WorkerError.fromJson(
        errorMap,
        fallbackMessage: 'Task pipeline returned terminal status $taskStatus',
        fallbackRetryable: taskStatus == WorkerResultStatus.retryable.name,
      );
    }

    _emit(
      _status.copyWith(
        phase: ExecutionPhase.submitting,
        progressMilli: output.progressMilli,
      ),
    );
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
    final taskMetrics = _taskMetricsFromOutput(
      output.metrics,
      startedAt: startedAt,
    )..inputBytes ??= bundle.inputBytes.length;
    final costFeedback = feedbackBuilder.build(
      metrics: taskMetrics,
      endSnapshot: endSnapshot,
    );
    final completionMetrics = Map<String, dynamic>.from(output.metrics)
      ..['costFeedback'] = costFeedback.toJson();

    final idempotencyKey = 'complete-${assignment.attemptId}';
    final completeBody = {
      'leaseToken': assignment.leaseToken,
      'fenceToken': assignment.fenceToken,
      'resultSha256': resultSha256,
      'outputArtifactId': outputArtifactId,
      'outputInline': utf8.decode(output.resultBytes),
      'metrics': completionMetrics,
      'signature': signature,
    };
    await _resultOutbox.enqueue(idempotencyKey, completeBody);
    try {
      await _api.completeAssignment(
        assignmentId: assignment.assignmentId,
        accessToken: _accessToken,
        idempotencyKey: idempotencyKey,
        body: completeBody,
      );
      await _resultOutbox.ack(idempotencyKey);
    } catch (_) {
      rethrow;
    }

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
    _emit(
      _status.copyWith(
        phase: ExecutionPhase.completed,
        progressMilli: 1000,
        detail: resultPreview,
        taskType: assignment.taskType,
        assignmentId: assignment.assignmentId,
        taskId: assignment.taskId,
      ),
    );
  }

  Future<void> safeStopAndCheckpoint(
    WorkerAssignment assignment,
    AssignmentInputBundle bundle,
    int progressMilli,
  ) async {
    _emit(
      _status.copyWith(
        phase: ExecutionPhase.checkpointing,
        progressMilli: progressMilli,
      ),
    );
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
    final checkpoint = await _checkpointStore.latestFor(
      assignment.assignmentId,
    );
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
      _log(
        '[FAILURE REQUEST] assignmentId=${assignment.assignmentId} '
        'code=${evidence.failureCode} retryable=${evidence.retryable}',
      );
      await _api.failAssignment(
        assignmentId: assignment.assignmentId,
        accessToken: _accessToken,
        idempotencyKey: 'fail-${assignment.attemptId}-${evidence.failureCode}',
        body: evidence.toFailRequest(leaseToken: assignment.leaseToken),
      );
      _log('[FAILURE RESPONSE] worker-gateway accepted failure evidence');
    } finally {
      _storagePressure.clearActiveAssignment();
      if (_assignmentStarted) {
        await _cleanup(assignment, preserveCheckpoint: checkpoint != null);
        await _platform.stopForegroundService();
      }
      _emit(
        _status.copyWith(
          phase: ExecutionPhase.failed,
          detail: evidence.failureCode,
          assignmentId: assignment.assignmentId,
          taskId: assignment.taskId,
          taskType: assignment.taskType,
        ),
      );
    }
  }

  Future<void> abandon(
    WorkerAssignment assignment, {
    required String reason,
  }) async {
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

  void _startLeaseRenewal(WorkerAssignment assignment) {
    _stopLeaseRenewal();
    final now = DateTime.now().toUtc();
    final ttl = assignment.leaseExpiresAt.difference(now);
    if (ttl.isNegative) {
      return;
    }
    final renewIn = Duration(
      milliseconds: (ttl.inMilliseconds * 0.7).round().clamp(
        5000,
        ttl.inMilliseconds,
      ),
    );
    _leaseRenewSequence = 0;
    _leaseRenewalTimer = Timer(renewIn, () async {
      if (!_assignmentStarted || _cancelRequested) {
        return;
      }
      try {
        _leaseRenewSequence += 1;
        await _api.renewAssignment(
          assignmentId: assignment.assignmentId,
          accessToken: _accessToken,
          leaseToken: assignment.leaseToken,
          fenceToken: assignment.fenceToken,
          sequence: _leaseRenewSequence,
          idempotencyKey: 'renew-${assignment.attemptId}-$_leaseRenewSequence',
        );
      } catch (_) {
        _cancelRequested = true;
      }
    });
  }

  void _stopLeaseRenewal() {
    _leaseRenewalTimer?.cancel();
    _leaseRenewalTimer = null;
  }

  Future<void> _cleanup(
    WorkerAssignment assignment, {
    bool preserveCheckpoint = false,
  }) async {
    _stopLeaseRenewal();
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
      ExecutionPhase.failed => const [],
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

  static Future<AssignmentInputBundle> _defaultInputLoader(
    WorkerAssignment assignment,
  ) async {
    final inputBytes = Uint8List.fromList(
      'input-for-${assignment.taskType}'.codeUnits,
    );
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
