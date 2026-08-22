import 'dart:convert';
import 'dart:typed_data';

import '../api/worker_api_client.dart';
import '../api/worker_assignment_models.dart';
import '../platform/worker_runtime_channel.dart';
import 'checkpoint_store.dart';
import 'device_constraints.dart';
import 'device_snapshot.dart';
import 'encrypted_store.dart';
import 'execution_policy.dart';
import 'execution_status.dart';
import 'inference_adapter.dart';
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
    this.manifest = const {},
    this.isImageInput = false,
  });

  final Uint8List inputBytes;
  final String inputDigest;
  final ModelArtifact modelArtifact;
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
    SandboxLimits? sandbox,
    InputLoader? inputLoader,
    TaskExecutionEngine? taskEngine,
    String? accessToken,
    StatusListener? onStatus,
  })  : _api = api,
        _checkpointStore = CheckpointStore(store),
        _platform = platform,
        _inference = inference,
        _constraints = constraints ?? const DeviceConstraints(),
        _sandbox = sandbox ?? const SandboxLimits(),
        _inputLoader = inputLoader ?? _defaultInputLoader,
        _taskEngine = taskEngine,
        _accessToken = accessToken ?? 'token',
        _onStatus = onStatus;

  final WorkerApiClient _api;
  final CheckpointStore _checkpointStore;
  final WorkerRuntimeChannel _platform;
  final InferenceAdapter _inference;
  final DeviceConstraints _constraints;
  final SandboxLimits _sandbox;
  final InputLoader _inputLoader;
  final TaskExecutionEngine? _taskEngine;
  final String _accessToken;
  final StatusListener? _onStatus;

  ExecutionStatus _status = const ExecutionStatus(phase: ExecutionPhase.idle);
  bool _cancelRequested = false;

  ExecutionStatus get status => _status;

  void _emit(ExecutionStatus next) {
    _status = next;
    _onStatus?.call(next);
  }

  Future<WorkerAssignment?> pollAssignment({
    DeviceSnapshot? snapshot,
    int waitSeconds = 0,
  }) async {
    _emit(_status.copyWith(phase: ExecutionPhase.waitingForAssignment));
    final device = snapshot ?? await _platform.readDeviceSnapshot();
    _constraints.ensureOrThrow(device);
    return _api.getNextAssignment(accessToken: _accessToken, waitSeconds: waitSeconds);
  }

  Future<ResumeDecision> inspectResume(WorkerAssignment assignment, AssignmentInputBundle bundle) async {
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
    ResumeDecision? resume,
  }) async {
    _cancelRequested = false;
    final startedAt = DateTime.now();
    final device = snapshot ?? await _platform.readDeviceSnapshot();
    _constraints.ensureOrThrow(device, heavyTask: true);

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
    final decision = resume ?? await inspectResume(assignment, bundle);
    if (decision.checkpoint != null && assignment.fenceToken != decision.checkpoint!.fenceToken) {
      throw StaleFenceException(assignment.fenceToken, decision.checkpoint!.fenceToken);
    }

    final signingMaterial = await _platform.signingMaterial();
    await _inference.loadVerified(bundle.modelArtifact, signingKey: signingMaterial);

    await _api.reportAssignmentStarted(
      assignmentId: assignment.assignmentId,
      accessToken: _accessToken,
      leaseToken: assignment.leaseToken,
      fenceToken: assignment.fenceToken,
      idempotencyKey: 'start-${assignment.attemptId}',
    );

    _emit(_status.copyWith(phase: ExecutionPhase.running, progressMilli: decision.checkpoint?.progressMilli ?? 0));

    var lastReportedProgress = decision.checkpoint?.progressMilli ?? 0;
    final usePipeline =
        _taskEngine != null && TaskTypeMapper.isPipelineTask(assignment.taskType);
    Future<void> onProgressWrapper(int progressMilli) async {
      if (_cancelRequested) {
        throw const LeaseRevokedException();
      }
      final current = await _platform.readDeviceSnapshot();
      final constraint = _constraints.evaluate(current, heavyTask: true);
      if (!constraint.allowed) {
        throw ConstraintBlockedException(constraint.violation!, constraint.detail);
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
      output = await _taskEngine!.execute(
        context: TaskExecutionContext(
          assignment: assignment,
          manifest: bundle.manifest,
          inputBytes: bundle.inputBytes,
          isImageInput: bundle.isImageInput,
        ),
        signingKey: signingMaterial,
        freeStorageMb: device.freeStorageMb,
        isCancelled: () => _cancelRequested,
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
    final signer = ResultSigner(signingMaterial: signingMaterial);
    final signature = signer.sign(
      assignmentId: assignment.assignmentId,
      fenceToken: assignment.fenceToken,
      resultSha256: resultSha256,
      outputArtifactId: outputArtifactId,
    );

    await _api.completeAssignment(
      assignmentId: assignment.assignmentId,
      accessToken: _accessToken,
      idempotencyKey: 'complete-${assignment.attemptId}',
      body: {
        'leaseToken': assignment.leaseToken,
        'fenceToken': assignment.fenceToken,
        'resultSha256': resultSha256,
        'outputArtifactId': outputArtifactId,
        'metrics': output.metrics,
        'signature': signature,
      },
    );

    await _cleanup(assignment.assignmentId);
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

  Future<void> abandon(WorkerAssignment assignment, {required String reason}) async {
    await _api.abandonAssignment(
      assignmentId: assignment.assignmentId,
      accessToken: _accessToken,
      leaseToken: assignment.leaseToken,
      fenceToken: assignment.fenceToken,
      reason: reason,
      idempotencyKey: 'abandon-${assignment.attemptId}',
    );
    await _cleanup(assignment.assignmentId);
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

  Future<void> _cleanup(String assignmentId) async {
    _emit(_status.copyWith(phase: ExecutionPhase.cleaningUp));
    await _checkpointStore.purge(assignmentId);
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
  });

  final bool startFresh;
  final CheckpointRecord? checkpoint;
  final Uint8List? resumedState;
  final bool discardedStaleCheckpoint;
}
