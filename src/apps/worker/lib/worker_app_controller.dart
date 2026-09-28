import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:http/http.dart' as http;

import 'api/worker_api_client.dart';
import 'api/worker_assignment_models.dart';
import 'api/worker_routes.dart';
import 'config/worker_config.dart';
import 'contracts/worker_error.dart';
import 'inference/llm/qwen_task_processor.dart';
import 'inference/llm/summarize_diagnostic_map.dart';
import 'inference/llm/diagnostic/summarize_map_evidence_diagnostic_fixture.dart';
import 'inference/llm/diagnostic/facts_only_experiment.dart';
import 'inference/llm/diagnostic/summarize_map_prompt_variant.dart';
import 'inference/ocr/gemma_multimodal_ocr_engine.dart';
import 'inference/ocr/guarded_ocr_engine.dart';
import 'inference/ocr/fake_ocr_engine.dart';
import 'inference/ocr/ocr_engine.dart';
import 'inference/ocr/paddle_ocr_engine.dart';
import 'inference/ocr/paddle_ocr_installer.dart';
import 'models/worker_model_catalog.dart';
import 'platform/worker_runtime_channel.dart';
import 'runtime/assignment_coordinator.dart';
import 'runtime/assignment_output_upload_coordinator.dart';
import 'runtime/checkpoint_manager.dart';
import 'runtime/dev_mock_inference_adapter.dart';
import 'runtime/device_snapshot.dart';
import 'runtime/encrypted_store.dart';
import 'runtime/execution_status.dart';
import 'runtime/gemma_bootstrap.dart';
import 'runtime/gemma_inference_adapter.dart';
import 'runtime/identity_lifecycle_tracer.dart';
import 'runtime/model_download_verify_hook.dart';
import 'runtime/process_lifecycle_coordinator.dart';
import 'runtime/runtime_exclusive_group_enforcer.dart';
import 'runtime/inference_adapter.dart';
import 'runtime/storage_pressure_manager.dart';
import 'runtime/switchable_inference_adapter.dart';
import 'runtime/worker_access_token_provider.dart';
import 'runtime/worker_process_memory_telemetry.dart';
import 'runtime/worker_heartbeat_service.dart';
import 'runtime/worker_pipeline_log.dart';
import 'runtime/worker_content_diagnostics.dart';
import 'runtime/worker_session_lifecycle.dart';
import 'runtime/worker_session_store.dart';
import 'tasks/task_execution_engine.dart';
import 'tasks/task_type_mapper.dart';
import 'runtime/gemma_model_runtime_manager.dart';
import 'runtime/worker_model_installer.dart';

enum ModelInstallPhase { idle, downloading, ready, failed }

/// Default OCR uses the resident Gemma multimodal path; opt in to Paddle ONNX.
abstract final class WorkerOcrBackendPolicy {
  static const usePaddleOcr = bool.fromEnvironment(
    'WORKER_USE_PADDLE_OCR',
    defaultValue: false,
  );
}

class WorkerAppController extends ChangeNotifier {
  WorkerAppController({
    WorkerConfig? config,
    http.Client? httpClient,
    WorkerRuntimeChannel? platform,
    OcrEngine? ocrEngine,
    QwenTaskProcessor? qwenProcessor,
    TaskExecutionEngine? taskEngine,
    StoragePressureManager? storagePressure,
    EncryptedStore? encryptedStore,
  }) : _config = config ?? WorkerConfig.fromEnvironment(),
       _http = httpClient ?? http.Client(),
       _platform = platform ?? WorkerRuntimeChannel(),
       _storagePressure = storagePressure ?? StoragePressureManager(),
       _encryptedStore = encryptedStore ?? InMemoryEncryptedStore() {
    _exclusiveGroups = RuntimeExclusiveGroupEnforcer();
    _runtimeManager = GemmaModelRuntimeManager(
      exclusiveGroupEnforcer: _exclusiveGroups,
    );
    const inferenceConfig = QwenInferenceConfig();
    _primaryInferenceAdapter = GemmaLiteRtInferenceAdapter(
      runtimeManager: _runtimeManager,
      maxOutputTokens: inferenceConfig.maxOutputTokens,
    );
    _inference = SwitchableInferenceAdapter(_primaryInferenceAdapter);

    _checkpointManager = CheckpointManager(_encryptedStore);
    _qwenProcessor =
        qwenProcessor ??
        QwenTaskProcessor(
          adapter: _primaryInferenceAdapter,
          checkpointManager: _checkpointManager,
          config: inferenceConfig,
          log: (message) =>
              WorkerPipelineLog.info(WorkerPipelineLog.exec, message),
        );
    _ocrEngineRef = OcrEngineRef(
      _wrapOcrEngine(
        ocrEngine ??
            (WorkerOcrBackendPolicy.usePaddleOcr
                ? PaddleOcrEngine()
                : GemmaMultimodalOcrEngine(_qwenProcessor)),
      ),
    );

    _accessTokenProvider = WorkerAccessTokenProvider(
      initialToken: _workerAccessToken,
      readToken: () => _runtimeAccessToken,
    );

    _taskEngine =
        taskEngine ??
        TaskExecutionEngine(
          ocrEngine: _ocrEngineRef,
          qwenProcessor: _qwenProcessor,
          exclusiveGroupEnforcer: _exclusiveGroups,
        );

    _api = WorkerApiClient(
      config: _config,
      httpClient: _http,
      devClaimAssignments: _devClaimAssignments,
      onAudit: ({required method, required path, required status}) {
        WorkerPipelineLog.info(
          WorkerPipelineLog.api,
          '$method $path -> $status',
        );
      },
    );

    _processLifecycle = ProcessLifecycleCoordinator(
      onInvalidateNativeHandles: (_) async {
        _inference.dispose();
        await _qwenProcessor.dispose();
      },
    );

    _sessionStore = WorkerSessionStore(_encryptedStore);
    _sessionLifecycle = WorkerSessionLifecycle(
      api: _api,
      store: _sessionStore,
      platform: _platform,
    );

    _coordinator = AssignmentCoordinator(
      api: _api,
      store: _encryptedStore,
      platform: _platform,
      inference: _inference,
      inputLoader: _loadAssignmentInput,
      taskEngine: _taskEngine,
      storagePressure: _storagePressure,
      accessTokenProvider: _accessTokenProvider,
      accessToken: _runtimeAccessToken,
      onStatus: _onExecutionStatus,
      onLog: (message) =>
          WorkerPipelineLog.info(WorkerPipelineLog.exec, message),
      processLifecycle: _processLifecycle,
    );
    _storagePressure.seedDefaultCatalog();
    _refreshHeartbeat();
  }

  static Future<WorkerAppController> create() async {
    final platform = WorkerRuntimeChannel();
    EncryptedStore store = InMemoryEncryptedStore();
    try {
      final path = await platform.localStorePath();
      if (path != null && path.isNotEmpty) {
        store = await PersistentEncryptedStore.open(path);
      }
    } catch (error, stackTrace) {
      WorkerPipelineLog.error(
        WorkerPipelineLog.boot,
        'Persistent store unavailable; using in-memory store',
        error,
        stackTrace,
      );
    }
    return WorkerAppController(platform: platform, encryptedStore: store);
  }

  WorkerConfig _config;

  final http.Client _http;
  final WorkerRuntimeChannel _platform;
  final EncryptedStore _encryptedStore;

  late final WorkerApiClient _api;
  late final SwitchableInferenceAdapter _inference;
  late final GemmaModelRuntimeManager _runtimeManager;
  late final GemmaLiteRtInferenceAdapter _primaryInferenceAdapter;
  late final WorkerAccessTokenProvider _accessTokenProvider;

  late final RuntimeExclusiveGroupEnforcer _exclusiveGroups;
  late final OcrEngineRef _ocrEngineRef;
  Future<bool>? _modelReadyFuture;

  late final CheckpointManager _checkpointManager;
  late final QwenTaskProcessor _qwenProcessor;
  late final TaskExecutionEngine _taskEngine;
  late final AssignmentCoordinator _coordinator;
  late final ProcessLifecycleCoordinator _processLifecycle;
  late final WorkerSessionStore _sessionStore;
  late final WorkerSessionLifecycle _sessionLifecycle;
  final StoragePressureManager _storagePressure;
  WorkerHeartbeatService? _heartbeat;

  DevMockInferenceAdapter? _devMockAdapter;

  OcrEngine _wrapOcrEngine(OcrEngine delegate) {
    if (delegate is GuardedOcrEngine) {
      return delegate;
    }
    return GuardedOcrEngine(
      delegate: delegate,
      exclusiveGroups: _exclusiveGroups,
    );
  }

  // ---------------------------------------------------------------------------
  // Runtime state
  // ---------------------------------------------------------------------------

  bool available = true;

  bool backendOnline = false;

  String backendMessage = 'Checking backend...';

  ModelInstallPhase modelPhase = ModelInstallPhase.idle;

  double modelProgress = 0;

  String? modelError;

  ExecutionStatus executionStatus = const ExecutionStatus(
    phase: ExecutionPhase.idle,
  );

  String? lastPortalTaskId;

  String? lastAssignmentId;

  final AssignmentOutputUploadCoordinator _outputUploadCoordinator =
      AssignmentOutputUploadCoordinator();

  String lastSync = 'never';

  int batteryPercent = 100;

  bool isCharging = false;

  bool isEmulator = false;

  bool isX86Android = false;

  bool usesDevMockInference = false;

  int freeStorageMb = 0;

  bool ocrModelsReady = false;

  String thermalLabel = 'Normal';

  int tasksProcessed = 0;

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  static const _assignmentPollInterval = Duration(seconds: 2);

  static const _assignmentLongPollSeconds = 20;

  /// Dev Mock is now explicit.
  ///
  /// It is NOT automatically enabled on x86.
  ///
  /// Enable with:
  ///
  /// --dart-define=WORKER_USE_DEV_MOCK=true
  ///
  static const _devMockRequested = bool.fromEnvironment(
    'WORKER_USE_DEV_MOCK',
    defaultValue: false,
  );

  /// Pins dev assignments to this worker device on first poll (local dev default).
  static const _devClaimAssignments = bool.fromEnvironment(
    'EDGEMINT_DEV_CLAIM_ASSIGNMENTS',
    defaultValue: true,
  );

  static const _workerId = String.fromEnvironment(
    'EDGEMINT_WORKER_ID',
    defaultValue: '',
  );

  static const _workerAccessToken = String.fromEnvironment(
    'EDGEMINT_WORKER_ACCESS_TOKEN',
    defaultValue: '',
  );

  String _runtimeWorkerId = _workerId;
  String? _runtimeDeviceId;
  String _runtimeAccessToken = _workerAccessToken;
  DateTime? _runtimeTokenExpiresAt;
  bool workerEnrolled = false;
  String? enrollmentMessage;
  int _lastHeartbeatSequence = 0;
  bool _enrollmentPermanentlyBlocked = false;
  DateTime? _nextEnrollmentAttemptAt;
  int _enrollmentAttempts = 0;

  static const _maxEnrollmentRetries = 5;

  int _assignmentLoopGeneration = 0;

  String get workerId => _runtimeWorkerId;

  String? get deviceId => _runtimeDeviceId;

  bool get hasManualCredentials =>
      _workerId.isNotEmpty && _workerAccessToken.isNotEmpty;

  void _applyWorkerSession(WorkerSessionRecord session) {
    _runtimeWorkerId = session.workerId;
    _runtimeDeviceId = session.deviceId;
    _runtimeAccessToken = session.accessToken;
    _runtimeTokenExpiresAt = session.expiresAt;
    _lastHeartbeatSequence = session.lastHeartbeatSequence;
    _accessTokenProvider.update(session.accessToken);
    workerEnrolled = true;
    enrollmentMessage = null;
    _refreshHeartbeat();
  }

  void updateWorkerAccessToken(String token) {
    _runtimeAccessToken = token;
    _accessTokenProvider.update(token);
    _refreshHeartbeat();
    notifyListeners();
  }

  void _refreshHeartbeat() {
    final token = _accessTokenProvider.current;
    if (_runtimeWorkerId.isNotEmpty && token.isNotEmpty) {
      _heartbeat ??= WorkerHeartbeatService(
        api: _api,
        workerId: _runtimeWorkerId,
        accessToken: token,
        initialSequence: _lastHeartbeatSequence,
      );
      _heartbeat!.updateCredentials(
        workerId: _runtimeWorkerId,
        accessToken: token,
      );
      _heartbeat!.resetSequence(_lastHeartbeatSequence);
      return;
    }
    _heartbeat = null;
  }

  Future<void> _persistHeartbeatSequence(int sequence) async {
    if (sequence <= _lastHeartbeatSequence) {
      return;
    }
    _lastHeartbeatSequence = sequence;
    final session = await _sessionStore.readSession();
    if (session == null || session.workerId != _runtimeWorkerId) {
      return;
    }
    await _sessionStore.writeSession(
      session.copyWith(lastHeartbeatSequence: sequence),
    );
  }

  bool _disposed = false;

  bool _processingAssignment = false;

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  bool get isAutoAssigning => available && backendOnline && !_disposed;

  bool get isGemmaReady => modelPhase == ModelInstallPhase.ready;

  bool get isGemmaDownloading => modelPhase == ModelInstallPhase.downloading;

  bool get canStartGemmaDownload => modelPhase != ModelInstallPhase.downloading;

  bool get canAcceptAssignments =>
      backendOnline &&
      !isGemmaDownloading &&
      available &&
      (usesDevMockInference || isGemmaReady) &&
      (hasManualCredentials || workerEnrolled);

  bool get canPollAssignments => canAcceptAssignments;

  bool get mapEvidenceDiagnosticArmed => SummarizeDiagnosticMap.armed;

  /// Isolated Map evidence diagnostic — never uploads assignment output.
  Future<SummarizeMapEvidenceDiagnosticResult> runIsolatedMapEvidenceDiagnostic({
    SummarizeMapEvidenceDiagnosticFixtureId fixtureId =
        SummarizeMapEvidenceDiagnosticFixtureId.baselineFactLines,
  }) async {
    SummarizeDiagnosticMap.assertArmedOrThrow();
    final result = await _withDiagnosticModelLock(() async {
      await ensureModelReady();
      final signingMaterial = await _platform.signingMaterial();
      _logTask(
        '[DIAGNOSTIC MAP EVIDENCE] starting isolated run '
        'fixture=${fixtureId.logLabel} '
        '(does not complete or upload a portal assignment)',
        phase: WorkerPipelineLog.exec,
      );
      return _qwenProcessor.runIsolatedMapEvidenceDiagnostic(
        signingKey: signingMaterial,
        fixtureId: fixtureId,
      );
    });
    if (result.promptVariant == SummarizeMapPromptVariant.factsOnly) {
      final snapshot = result.factsSnapshot;
      if (snapshot == null) {
        _factsOnlySnapshots.remove(fixtureId);
      } else {
        _factsOnlySnapshots[fixtureId] = snapshot;
      }
    }
    _logTask(
      '[DIAGNOSTIC MAP EVIDENCE] finished runId=${result.runId} '
      'fixture=${result.fixtureId.logLabel} '
      'variant=${result.promptVariant.logLabel} '
      'stage=${result.inferenceStage} truncated=${result.truncated} '
      'stopReason=${result.stopReason} firstPassSuccess=${result.firstPassSuccess} '
      'repairedSuccess=${result.repairedSuccess} '
      'correctiveInferenceCalls=${result.correctiveInferenceCalls}',
      phase: WorkerPipelineLog.exec,
    );
    return result;
  }

  final Map<SummarizeMapEvidenceDiagnosticFixtureId, FactsOnlyExtractionSnapshot>
      _factsOnlySnapshots = {};

  bool get factsOnlyDiagnosticSelected =>
      SummarizeDiagnosticMap.armed &&
      SummarizeDiagnosticMap.promptVariant == SummarizeMapPromptVariant.factsOnly;

  /// Latest accepted facts-only extraction not yet classified, if any.
  FactsOnlyExtractionSnapshot? classifiableFactsSnapshot(
    SummarizeMapEvidenceDiagnosticFixtureId fixtureId,
  ) {
    final snapshot = _factsOnlySnapshots[fixtureId];
    if (snapshot == null || snapshot.classificationStarted) {
      return null;
    }
    return snapshot;
  }

  /// Facts-only Step 2 on the fixture's latest accepted extraction; never uploads.
  Future<FactsClassificationDiagnosticResult> runFactsOnlyClassificationDiagnostic({
    required SummarizeMapEvidenceDiagnosticFixtureId fixtureId,
  }) async {
    SummarizeDiagnosticMap.assertArmedOrThrow();
    final snapshot = classifiableFactsSnapshot(fixtureId);
    if (snapshot == null) {
      throw WorkerError(
        code: WorkerErrorCode.invalidTask,
        message:
            'No accepted, unclassified facts-only extraction for '
            '${fixtureId.logLabel}; run facts-only extraction first',
        retryable: false,
        stage: WorkerTaskStage.validation,
      );
    }
    final result = await _withDiagnosticModelLock(() async {
      await ensureModelReady();
      final signingMaterial = await _platform.signingMaterial();
      _logTask(
        '[DIAGNOSTIC FACTS CLASSIFICATION] starting '
        'experimentId=${snapshot.experimentId} '
        'extractionRunId=${snapshot.extractionRunId} '
        '(does not complete or upload a portal assignment)',
        phase: WorkerPipelineLog.exec,
      );
      return _qwenProcessor.runFactsOnlyClassificationDiagnostic(
        signingKey: signingMaterial,
        snapshot: snapshot,
      );
    });
    _logTask(
      '[DIAGNOSTIC FACTS CLASSIFICATION] finished '
      'classificationRunId=${result.classificationRunId} '
      'firstPassSuccess=${result.firstPassSuccess} '
      'repairedSuccess=${result.repairedSuccess} '
      'correctiveCallsExperimentTotal=${result.correctiveCallsExperimentTotal}',
      phase: WorkerPipelineLog.exec,
    );
    return result;
  }

  /// Holds the assignment-processing flag so polling cannot start a model run
  /// while a diagnostic uses the model, and rejects overlapping diagnostics.
  Future<T> _withDiagnosticModelLock<T>(Future<T> Function() body) async {
    if (_processingAssignment || _isBusyExecuting) {
      throw WorkerError(
        code: WorkerErrorCode.invalidTask,
        message: 'Model is busy with another assignment or diagnostic run',
        retryable: true,
        stage: WorkerTaskStage.validation,
      );
    }
    _processingAssignment = true;
    try {
      return await body();
    } finally {
      _processingAssignment = false;
    }
  }

  bool get requiresHuggingFaceToken => false;

  bool get _isBusyExecuting => switch (executionStatus.phase) {
    ExecutionPhase.preparing ||
    ExecutionPhase.running ||
    ExecutionPhase.checkpointing ||
    ExecutionPhase.submitting ||
    ExecutionPhase.cleaningUp => true,
    _ => false,
  };

  // ---------------------------------------------------------------------------
  // Logging
  // ---------------------------------------------------------------------------

  void _logTask(String message, {String phase = WorkerPipelineLog.boot}) {
    WorkerPipelineLog.info(phase, message);
  }

  static const _verboseTaskLogs = bool.fromEnvironment(
    'WORKER_VERBOSE_TASK_LOGS',
    defaultValue: false,
  );

  String _preview(String value, {int maxLength = 300}) {
    final normalized = value.replaceAll('\n', ' ');

    if (normalized.length <= maxLength) {
      return normalized;
    }

    return '${normalized.substring(0, maxLength)}...';
  }

  void _logError(
    String message,
    Object error, [
    StackTrace? stackTrace,
    String phase = WorkerPipelineLog.boot,
  ]) {
    WorkerPipelineLog.error(phase, message, error, stackTrace);
  }

  // ---------------------------------------------------------------------------
  // Bootstrap
  // ---------------------------------------------------------------------------

  Future<void> bootstrap() async {
    _logTask('Worker bootstrap started', phase: WorkerPipelineLog.boot);

    await _platform.setConsentsGranted(const [
      'terms',
      'privacy',
      'resource_use',
      'reward_disclosure',
    ]);

    await _resolveBackendUrl();

    await _refreshBackendHealth();

    if (backendOnline) {
      await _ensureWorkerSession();
    }

    await _refreshDeviceReadiness();

    try {
      await ensureModelReady();
    } catch (error, stackTrace) {
      _logError('Model check failed', error, stackTrace);

      if (!usesDevMockInference &&
          modelPhase != ModelInstallPhase.downloading) {
        modelPhase = ModelInstallPhase.idle;
      }
    }

    if (SummarizeDiagnosticMap.invokeAtStartup) {
      try {
        await runIsolatedMapEvidenceDiagnostic(
          fixtureId: SummarizeDiagnosticMap.defaultFixtureId,
        );
      } catch (error, stackTrace) {
        _logError(
          'SUMMARIZE_DIAGNOSTIC_INVOKE_AT_STARTUP failed',
          error,
          stackTrace,
        );
      }
    }

    notifyListeners();

    if (available) {
      startAutoAssignmentLoop();
    }

    _logTask(
      'Worker bootstrap completed: '
      'model=${WorkerModelCatalog.displayName}, '
      'phase=$modelPhase, '
      'emulator=$isEmulator, '
      'x86=$isX86Android, '
      'mock=$usesDevMockInference',
    );
  }

  // ---------------------------------------------------------------------------
  // Availability
  // ---------------------------------------------------------------------------

  void setAvailable(bool value) {
    if (available == value) {
      return;
    }

    available = value;

    if (value) {
      _logTask('Worker availability enabled - listening for assignments');

      startAutoAssignmentLoop();
    } else {
      _logTask('Worker availability disabled - auto-assignment paused');

      stopAutoAssignmentLoop();

      if (executionStatus.phase == ExecutionPhase.waitingForAssignment) {
        executionStatus = const ExecutionStatus(phase: ExecutionPhase.idle);
      }
    }

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Auto assignment
  // ---------------------------------------------------------------------------

  void startAutoAssignmentLoop() {
    if (_disposed || !available) {
      return;
    }

    _assignmentLoopGeneration++;

    final generation = _assignmentLoopGeneration;

    unawaited(_runAutoAssignmentLoop(generation));
  }

  void stopAutoAssignmentLoop() {
    _assignmentLoopGeneration++;
  }

  Future<void> _runAutoAssignmentLoop(int generation) async {
    _logTask('Auto-assignment loop started', phase: WorkerPipelineLog.assign);

    while (!_disposed && generation == _assignmentLoopGeneration && available) {
      if (!canAcceptAssignments) {
        await Future<void>.delayed(_assignmentPollInterval);

        continue;
      }

      if (_processingAssignment || _isBusyExecuting) {
        await Future<void>.delayed(_assignmentPollInterval);

        continue;
      }

      await _processNextAssignment(
        announceEmptyQueue: false,
        waitSeconds: _assignmentLongPollSeconds,
      );

      if (_disposed || generation != _assignmentLoopGeneration || !available) {
        break;
      }

      await Future<void>.delayed(_assignmentPollInterval);
    }

    if (generation == _assignmentLoopGeneration) {
      _logTask('Auto-assignment loop stopped', phase: WorkerPipelineLog.assign);
    }
  }

  // ---------------------------------------------------------------------------
  // Device readiness
  // ---------------------------------------------------------------------------

  Future<void> _refreshDeviceReadiness() async {
    try {
      final snapshot = await _platform.readDeviceSnapshot();

      batteryPercent = snapshot.batteryPercent;

      isCharging = snapshot.isCharging;

      isEmulator = snapshot.isEmulator;

      isX86Android = snapshot.isX86Android;

      _runtimeManager.configurePreferredBackend(
        WorkerModelCatalog.preferredInferenceBackend(isX86Android: isX86Android),
      );

      freeStorageMb = snapshot.freeStorageMb;

      thermalLabel = switch (snapshot.thermalState) {
        ThermalState.normal => 'Normal',
        ThermalState.warm => 'Warm',
        ThermalState.throttled => 'Throttled',
        ThermalState.critical => 'Critical',
      };

      if (isEmulator) {
        _logTask(
          'Emulator detected - battery treated as AC power for development',
        );
      }

      //
      // IMPORTANT CHANGE:
      //
      // x86 is no longer automatically mapped to Dev Mock.
      //
      // Gemma 4 `.litertlm` requires arm64-v8a; x86 emulators need
      // WORKER_USE_DEV_MOCK=true or a physical ARM device.
      //
      if (_devMockRequested) {
        _enableDevMockInference();

        _ocrEngineRef.delegate = _wrapOcrEngine(FakeOcrEngine());

        ocrModelsReady = true;

        _logTask(
          'WORKER_USE_DEV_MOCK=true - '
          'mock LLM and mock OCR enabled',
        );

        return;
      }

      if (isX86Android) {
        _logTask(
          'Android x86/x86_64 detected - '
          '${WorkerModelCatalog.displayName} uses CPU backend '
          '(OpenCL/GPU unavailable on x86 emulator)',
        );
      } else {
        _logTask(
          'Android ARM device detected - '
          'real ${WorkerModelCatalog.displayName} inference enabled',
        );
      }

      //
      // OCR: Gemma multimodal (default) or Paddle ONNX (WORKER_USE_PADDLE_OCR=true).
      //
      if (WorkerOcrBackendPolicy.usePaddleOcr) {
        _ocrEngineRef.delegate = _wrapOcrEngine(PaddleOcrEngine());
        ocrModelsReady = await PaddleOcrModelInstaller.verifyOnDevice(
          log: _logTask,
        );
        if (!ocrModelsReady) {
          _logTask('PaddleOCR models are not installed on device');
        }
      } else {
        _ocrEngineRef.delegate = _wrapOcrEngine(
          GemmaMultimodalOcrEngine(_qwenProcessor),
        );
        ocrModelsReady = isGemmaReady;
        _logTask(
          'OCR uses ${WorkerModelCatalog.displayName} multimodal '
          '(no separate Paddle bundle)',
        );
      }
    } catch (error, stackTrace) {
      _logError('Device readiness probe failed', error, stackTrace);
    }
  }

  String get batteryLabel {
    if (isEmulator) {
      return isCharging
          ? '$batteryPercent% (emulator AC)'
          : '$batteryPercent% (emulator)';
    }

    return isCharging ? '$batteryPercent% (charging)' : '$batteryPercent%';
  }

  String get storageLabel {
    if (freeStorageMb >= 1024) {
      return '${(freeStorageMb / 1024).toStringAsFixed(1)} GB free';
    }

    return '$freeStorageMb MB free';
  }

  // ---------------------------------------------------------------------------
  // Backend
  // ---------------------------------------------------------------------------

  Future<void> refreshBackendHealth() async {
    await _resolveBackendUrl();

    await _refreshBackendHealth();

    notifyListeners();
  }

  Future<void> _resolveBackendUrl() async {
    for (final candidate in WorkerConfig.connectionCandidates()) {
      try {
        final config = WorkerConfig(baseUrl: candidate);
        final health = await _http
            .get(config.resolve('/health/live'))
            .timeout(const Duration(seconds: 5));
        if (health.statusCode != 200) {
          continue;
        }

        final workerProbe = await _http
            .post(
              config.resolve(WorkerRoutes.createChallenge),
              headers: const {
                'Content-Type': 'application/json',
                'Idempotency-Key': 'worker-api-probe',
              },
              body: jsonEncode({'installationId': 'worker-api-probe'}),
            )
            .timeout(const Duration(seconds: 5));
        if (!WorkerConfig.workerApiProbeStatusAcceptable(
          workerProbe.statusCode,
        )) {
          _logTask(
            'Skipping $candidate — worker enrollment route missing '
            '(HTTP ${workerProbe.statusCode})',
          );
          continue;
        }

        if (_config.baseUrl != candidate) {
          _logTask(
            'Backend reachable at $candidate '
            '(was ${_config.baseUrl})',
          );
          _config.baseUrl = candidate;
          _api.reconfigure(_config);
        }
        return;
      } catch (_) {
        continue;
      }
    }

    _logTask(
      'No worker-gateway candidate responded - tried '
      '${WorkerConfig.connectionCandidates().join(", ")}',
    );
  }

  Future<void> _ensureWorkerSession() async {
    if (hasManualCredentials) {
      workerEnrolled = true;
      enrollmentMessage = null;
      _refreshHeartbeat();
      return;
    }
    if (_enrollmentPermanentlyBlocked) {
      return;
    }
    final nextAttempt = _nextEnrollmentAttemptAt;
    if (nextAttempt != null && DateTime.now().isBefore(nextAttempt)) {
      return;
    }

    try {
      _logTask('Enrollment started', phase: WorkerPipelineLog.enroll);
      final snapshot = await _platform.readDeviceSnapshot();
      final session = await _sessionLifecycle.ensureSession(
        snapshotOverride: snapshot,
      );
      _applyWorkerSession(session);
      _enrollmentAttempts = 0;
      _nextEnrollmentAttemptAt = null;
      _logTask(
        'Worker enrolled: ${session.workerId} device=${session.deviceId}',
        phase: WorkerPipelineLog.enroll,
      );
      _logTask(
        'Heartbeat ready (lastSeq=$_lastHeartbeatSequence)',
        phase: WorkerPipelineLog.heartbeat,
      );
    } on WorkerApiException catch (error) {
      workerEnrolled = false;
      _enrollmentAttempts += 1;
      if (error.isNotFound) {
        _enrollmentPermanentlyBlocked = true;
        enrollmentMessage =
            'Enrollment endpoint unavailable: ${error.method} ${error.path}';
      } else {
        enrollmentMessage =
            'Enrollment failed (${error.method} ${error.path}: ${error.code})';
        if (_enrollmentAttempts >= _maxEnrollmentRetries) {
          _enrollmentPermanentlyBlocked = true;
        } else {
          _nextEnrollmentAttemptAt = DateTime.now().add(
            Duration(seconds: 15 * _enrollmentAttempts),
          );
        }
      }
      _logError('Worker enrollment failed', error);
    } catch (error, stackTrace) {
      workerEnrolled = false;
      _enrollmentAttempts += 1;
      enrollmentMessage = 'Enrollment failed';
      if (_enrollmentAttempts >= _maxEnrollmentRetries) {
        _enrollmentPermanentlyBlocked = true;
      } else {
        _nextEnrollmentAttemptAt = DateTime.now().add(
          Duration(seconds: 15 * _enrollmentAttempts),
        );
      }
      _logError('Worker enrollment failed', error, stackTrace);
    }

    notifyListeners();
  }

  Future<void> _refreshSessionIfNeeded() async {
    if (hasManualCredentials) {
      return;
    }
    final expiresAt = _runtimeTokenExpiresAt;
    if (expiresAt == null ||
        !expiresAt.isBefore(
          DateTime.now().toUtc().add(const Duration(hours: 1)),
        )) {
      return;
    }
    try {
      final session = await _sessionLifecycle.ensureSession();
      _applyWorkerSession(session);
    } catch (error, stackTrace) {
      _logError('Worker session refresh failed', error, stackTrace);
    }
  }

  Future<void> _refreshBackendHealth() async {
    try {
      final response = await _http
          .get(_config.resolve('/health/live'))
          .timeout(_config.requestTimeout);

      backendOnline = response.statusCode == 200;

      backendMessage = backendOnline
          ? 'Connected '
                '(${_config.baseUrl.host}:${_config.baseUrl.port})'
          : 'Unreachable '
                '(${_config.baseUrl.host}:${_config.baseUrl.port}). '
                'Open port 8081 in Windows Firewall and ensure '
                'the phone/emulator can reach the worker gateway.';
    } catch (error) {
      backendOnline = false;

      final hint = _config.baseUrl.host == '127.0.0.1'
          ? 'Run on PC: powershell -File tools/start_worker_dev.ps1'
          : 'Run tools/open_worker_gateway_firewall.ps1 '
                'as Administrator on the PC.';

      backendMessage =
          'Unreachable '
          '(${_config.baseUrl.host}:${_config.baseUrl.port}): '
          '$error. $hint';
    }

    lastSync = _formatNow();
  }

  Future<void> _sendHeartbeatIfConfigured() async {
    final heartbeat = _heartbeat;
    if (heartbeat == null) {
      return;
    }

    try {
      final snapshot = await _platform.readDeviceSnapshot();
      final installedModels = isGemmaReady
          ? [
              {
                'modelVersionId': WorkerModelCatalog.modelVersionId,
                'artifactSha256':
                    WorkerModelCatalog.pinnedDigestSha256.isNotEmpty
                    ? WorkerModelCatalog.pinnedDigestSha256
                    : WorkerModelCatalog.installedDigestMarker,
              },
            ]
          : const <Map<String, String>>[];
      final loadedModelIds = isGemmaReady
          ? [WorkerModelCatalog.modelVersionId]
          : const <String>[];

      final sequence = await heartbeat.send(
        context: _coordinator.heartbeatTelemetryContext(
          snapshot: snapshot,
          sequence: heartbeat.sequence,
          runtimeExclusiveGroups: _exclusiveGroups,
          installedModels: installedModels,
          loadedModelIds: loadedModelIds,
          identityLifecycleView: IdentityLifecycleTracer.instance.heartbeatView(
            runtimeGeneration: _processLifecycle.runtimeGeneration,
            nativeHandlesInvalidated:
                _processLifecycle.nativeHandlesInvalidated,
            hasActiveAssignment: _coordinator.activeAssignmentIds().isNotEmpty,
          ),
        ),
      );
      await _persistHeartbeatSequence(sequence);
    } catch (error, stackTrace) {
      _logError(
        'Heartbeat failed',
        error,
        stackTrace,
        WorkerPipelineLog.heartbeat,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Model readiness
  // ---------------------------------------------------------------------------

  Future<bool> ensureModelReady() {
    if (_modelReadyFuture != null) {
      return _modelReadyFuture!;
    }

    _modelReadyFuture = _ensureModelReadyInternal();

    return _modelReadyFuture!;
  }

  Future<bool> _installBundledAssetIfConfigured() async {
    final bundledAsset = WorkerModelCatalog.bundledAssetFromEnvironment();
    if (bundledAsset == null || usesDevMockInference) {
      return false;
    }

    if (await WorkerModelInstaller.verifyActive(log: _logTask)) {
      _setModelReady();
      return true;
    }

    if (modelPhase == ModelInstallPhase.downloading) {
      return false;
    }

    try {
      await GemmaBootstrap.ensureInitialized();

      _logTask(
        'Installing bundled model asset: '
        '$bundledAsset',
        phase: WorkerPipelineLog.model,
      );

      modelPhase = ModelInstallPhase.downloading;
      modelProgress = 0;
      notifyListeners();

      await WorkerModelInstaller.installBundledAsset(log: _logTask);

      if (await WorkerModelInstaller.ensureReady(log: _logTask)) {
        _setModelReady();
        _logTask(
          '${WorkerModelCatalog.displayName} '
          'installed from bundled asset',
          phase: WorkerPipelineLog.model,
        );
        return true;
      }
    } catch (error, stackTrace) {
      _logError('Bundled model install failed', error, stackTrace);
      modelPhase = ModelInstallPhase.failed;
      modelError = '$error';
    }

    notifyListeners();
    return false;
  }

  Future<bool> _ensureModelReadyInternal() async {
    return IdentityLifecycleTracer.instance.guardBootstrap(
      caller: 'WorkerAppController.ensureModelReady',
      body: () async {
        try {
          if (usesDevMockInference) {
            _setModelReady();
            return true;
          }

          if (await WorkerModelInstaller.verifyActive(log: _logTask)) {
            _setModelReady();
            return true;
          }

          final ready = await WorkerModelInstaller.ensureReady(log: _logTask);

          if (ready) {
            _setModelReady();
            return true;
          }

          if (await _installBundledAssetIfConfigured()) {
            return true;
          }
        } catch (error, stackTrace) {
          _logError('Model check failed', error, stackTrace);
        } finally {
          _modelReadyFuture = null;
        }

        return false;
      },
    );
  }
  // ---------------------------------------------------------------------------
  // Model cleanup
  // ---------------------------------------------------------------------------

  Future<void> _clearBrokenModelInstall() async {
    await _clearStaleDownloadTasks();

    _logTask(
      'Skipping active inference identity clear; '
      'preserving model registration',
    );
  }

  // ---------------------------------------------------------------------------
  // Dev mock
  // ---------------------------------------------------------------------------

  void _enableDevMockInference() {
    if (usesDevMockInference && _devMockAdapter != null) {
      _setModelReady();

      return;
    }

    usesDevMockInference = true;

    _devMockAdapter = DevMockInferenceAdapter();

    _inference.use(_devMockAdapter!);

    _setModelReady();

    _logTask(
      'Dev mock inference enabled - '
      'real on-device LLM inference is disabled',
    );
  }

  // ---------------------------------------------------------------------------
  // Model state
  // ---------------------------------------------------------------------------

  void _setModelReady() {
    IdentityLifecycleTracer.instance.recordMutation(
      kind: 'setModelReady',
      caller: 'WorkerAppController._setModelReady',
      afterState: {'modelPhase': ModelInstallPhase.ready.name},
    );
    modelPhase = ModelInstallPhase.ready;

    modelProgress = 1;

    modelError = null;

    if (executionStatus.phase == ExecutionPhase.preparing &&
        (executionStatus.detail?.contains('Install') ?? false)) {
      executionStatus = const ExecutionStatus(phase: ExecutionPhase.idle);
    }

    unawaited(_recordModelReadyMemory());
  }

  Future<void> _recordModelReadyMemory() async {
    try {
      final snap = await _platform.readDeviceSnapshot();
      WorkerProcessMemoryTelemetry.recordPhase(
        'model_ready',
        snap.toProcessMemorySnapshot(),
      );
    } catch (_) {
      // Telemetry must not affect model readiness.
    }
  }

  Future<void> _refreshModelState() async {
    await ensureModelReady();
  }

  Future<bool> _verifyAndMarkModelReady() async {
    try {
      if (await WorkerModelInstaller.verifyActive(log: _logTask)) {
        _setModelReady();

        return true;
      }

      if (await WorkerModelInstaller.ensureReady(log: _logTask)) {
        _setModelReady();

        return true;
      }
    } catch (error, stackTrace) {
      _logError('Model activation verification failed', error, stackTrace);
    }

    return false;
  }

  // ---------------------------------------------------------------------------
  // Model download
  // ---------------------------------------------------------------------------

  Future<void> downloadGemmaModel() async {
    if (usesDevMockInference) {
      _logTask(
        'Dev mock inference is active - '
        'no real model download required',
      );

      _setModelReady();

      notifyListeners();

      return;
    }

    if (modelPhase == ModelInstallPhase.downloading) {
      return;
    }

    if (await _verifyAndMarkModelReady()) {
      _logTask(
        '${WorkerModelCatalog.displayName} '
        'already active - skipping download',
      );

      lastSync = _formatNow();

      notifyListeners();

      return;
    }

    modelPhase = ModelInstallPhase.downloading;

    modelProgress = 0;

    modelError = null;

    notifyListeners();

    try {
      await GemmaBootstrap.ensureInitialized();
      final snapshot = await _platform.readDeviceSnapshot();
      _storagePressure.ensureHeadroomForWork(snapshot);
      await _clearStaleDownloadTasks();

      final bundledAsset = WorkerModelCatalog.bundledAssetFromEnvironment();

      var downloadUrl = WorkerModelCatalog.resolveDownloadUrl(_config.baseUrl);

      if (bundledAsset == null &&
          WorkerModelCatalog.usesBackendArtifactProxy()) {
        if (backendOnline) {
          _logTask(
            'Using backend model proxy: '
            '$downloadUrl',
          );
        } else {
          downloadUrl = WorkerModelCatalog.huggingFaceDownloadUrl;

          _logTask(
            'Backend offline - '
            'using direct Hugging Face URL: '
            '$downloadUrl',
          );
        }
      } else {
        _logTask(
          'Model download URL: '
          '$downloadUrl',
        );
      }

      _logTask(
        'Preparing ${WorkerModelCatalog.displayName} '
        '(${WorkerModelCatalog.approximateDownloadSize})',
      );

      final installer = WorkerModelCatalog.installBuilder();

      if (bundledAsset != null) {
        _logTask(
          'Installing model from bundled asset: '
          '$bundledAsset',
        );

        await WorkerModelInstaller.installBundledAsset(log: _logTask);
      } else {
        await _installFromNetworkWithFallback(installer, downloadUrl);
      }

      _logTask(
        'Model transfer completed - '
        'verifying inference activation',
      );

      if (!await _verifyAndMarkModelReady()) {
        throw StateError(
          'Download finished but '
          '${WorkerModelCatalog.displayName} '
          'could not be activated.',
        );
      }

      _logTask(
        '${WorkerModelCatalog.displayName} '
        'install verified - ready for inference',
      );
    } catch (error, stackTrace) {
      _logError('Model setup failed', error, stackTrace);

      modelPhase = ModelInstallPhase.failed;

      modelError = '$error';

      _logTask('Model setup failed: $error');
    }

    lastSync = _formatNow();

    notifyListeners();

    if (available && isGemmaReady) {
      startAutoAssignmentLoop();
    }
  }

  Future<void> _installFromNetworkWithFallback(
    InferenceInstallationBuilder installer,
    String primaryUrl,
  ) async {
    try {
      await _installFromNetwork(installer, primaryUrl);
    } catch (primaryError) {
      final fallbackUrl = WorkerModelCatalog.huggingFaceDownloadUrl;

      if (primaryUrl == fallbackUrl) {
        rethrow;
      }

      _logTask(
        'Primary model download failed '
        '($primaryError) - '
        'retrying via Hugging Face',
      );

      // Do not uninstall an already downloaded model.
      await _clearStaleDownloadTasks();

      await _installFromNetwork(installer, fallbackUrl);
    }
  }

  Future<void> _installFromNetwork(
    InferenceInstallationBuilder installer,
    String downloadUrl,
  ) async {
    _logTask(
      'Starting network install: '
      '$downloadUrl',
    );

    await installer.fromNetwork(downloadUrl, foreground: true).withProgress((
      progress,
    ) {
      modelProgress = progress / 100.0;

      if (progress == 0 || progress >= 100 || progress % 10 == 0) {
        _logTask(
          'Model download progress: '
          '${progress.toStringAsFixed(0)}%',
        );
      }

      notifyListeners();
    }).install();

    final signingMaterial = await _platform.signingMaterial();
    final path = await WorkerModelInstaller.installedModelPathForVerification();
    if (path != null) {
      await const ModelDownloadVerifyHook().verifyInstalledFileIfPinned(
        path: path,
        signingKey: signingMaterial,
        modelVersionId: WorkerModelCatalog.modelVersionId,
      );
      _logTask('Post-download model digest/signature verification passed');
    }
  }

  Future<void> _clearStaleDownloadTasks({bool forceReinstall = false}) async {
    if (forceReinstall) {
      final possibleModels = <String>{
        WorkerModelCatalog.fileName,
        'Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
        'Qwen3-0.6B.litertlm',
        'gemma-4-E4B-it.litertlm',
      };

      for (final modelId in possibleModels) {
        try {
          await FlutterGemma.uninstallModel(modelId);
        } catch (_) {
          // Ignore missing model.
        }
      }
    }

    try {
      await FileDownloader().reset(group: 'smart_downloads');

      if (forceReinstall) {
        _logTask(
          'Cleared partial model downloads '
          'before retry',
        );
      }
    } catch (error) {
      _logTask(
        'Could not reset download tasks: '
        '$error',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Model UI
  // ---------------------------------------------------------------------------

  String get modelDownloadUrl {
    if (usesDevMockInference) {
      return '';
    }

    if (WorkerModelCatalog.bundledAssetFromEnvironment() != null) {
      return '';
    }

    if (WorkerModelCatalog.usesBackendArtifactProxy() && backendOnline) {
      return WorkerModelCatalog.resolveDownloadUrl(_config.baseUrl);
    }

    return WorkerModelCatalog.huggingFaceDownloadUrl;
  }

  String get gemmaDownloadLabel => switch (modelPhase) {
    ModelInstallPhase.idle =>
      usesDevMockInference
          ? 'Dev mock ready'
          : 'Prepare ${WorkerModelCatalog.displayName}',

    ModelInstallPhase.downloading =>
      'Downloading '
          '${WorkerModelCatalog.displayName} '
          '${(modelProgress * 100).toStringAsFixed(0)}%',

    ModelInstallPhase.ready =>
      usesDevMockInference
          ? 'Dev mock ready'
          : '${WorkerModelCatalog.displayName} installed',

    ModelInstallPhase.failed => 'Retry ${WorkerModelCatalog.displayName} setup',
  };

  // ---------------------------------------------------------------------------
  // Task requirements
  // ---------------------------------------------------------------------------

  Future<bool> _assignmentNeedsLlm(WorkerAssignment assignment) async {
    final v1 = TaskTypeMapper.toV1(assignment.taskType);

    if (v1 == null) {
      return true;
    }

    return TaskTypeMapper.requiresLlm(v1);
  }

  Future<bool> _assignmentNeedsOcr(WorkerAssignment assignment) async {
    final v1 = TaskTypeMapper.toV1(assignment.taskType);

    if (v1 == null) {
      return false;
    }

    return TaskTypeMapper.requiresOcr(v1);
  }

  // ---------------------------------------------------------------------------
  // Assignment execution
  // ---------------------------------------------------------------------------

  Future<void> pollAndRunTask() => _processNextAssignment();

  Future<void> _processNextAssignment({
    bool announceEmptyQueue = true,
    int waitSeconds = 0,
  }) async {
    if (_processingAssignment) {
      return;
    }

    _processingAssignment = true;

    try {
      await _runAssignmentCycle(
        announceEmptyQueue: announceEmptyQueue,
        waitSeconds: waitSeconds,
      );
    } finally {
      _processingAssignment = false;
    }
  }

  Future<void> _runAssignmentCycle({
    required bool announceEmptyQueue,
    required int waitSeconds,
  }) async {
    _logTask('Checking for next assignment', phase: WorkerPipelineLog.assign);

    _logTask(
      'Worker base URL: '
      '${_config.baseUrl}',
    );

    _logTask(
      'Pre-checks: '
      'available=$available, '
      'modelPhase=$modelPhase, '
      'modelReady=$isGemmaReady, '
      'mock=$usesDevMockInference',
    );

    try {
      await _refreshBackendHealth();

      await _refreshDeviceReadiness();

      _logTask(
        'Device: '
        'battery=$batteryLabel '
        'emulator=$isEmulator '
        'x86=$isX86Android',
      );

      _logTask(
        'Backend health: '
        'online=$backendOnline '
        'message="$backendMessage"',
      );

      if (!backendOnline) {
        _logTask(
          'Assignment aborted - '
          'backend offline',
        );

        return;
      }

      if (!hasManualCredentials && !workerEnrolled) {
        await _ensureWorkerSession();
        if (!workerEnrolled) {
          _logTask(
            'Assignment aborted - '
            'worker not enrolled (${enrollmentMessage ?? "unknown"})',
          );
          return;
        }
      }

      await _refreshSessionIfNeeded();

      await _sendHeartbeatIfConfigured();

      if (!available) {
        _logTask(
          'Assignment aborted - '
          'worker availability is off',
        );

        return;
      }

      if (!isGemmaReady) {
        await ensureModelReady();
      }

      _logTask(
        'Model check: '
        'name=${WorkerModelCatalog.displayName}, '
        'phase=$modelPhase, '
        'ready=$isGemmaReady',
      );

      _logTask(
        'Polling assignments:next from worker-gateway',
        phase: WorkerPipelineLog.assign,
      );

      final assignment = await _coordinator.pollAssignment(
        waitSeconds: waitSeconds,
      );

      if (assignment == null) {
        _logTask('No tasks in queue');

        if (announceEmptyQueue) {
          executionStatus = const ExecutionStatus(
            phase: ExecutionPhase.idle,
            detail:
                'No tasks in queue. Create a task in the customer portal first.',
          );

          lastSync = _formatNow();
          notifyListeners();
        }

        return;
      }

      _logTask(
        '[ASSIGNMENT RECEIVED] '
        'assignmentId=${assignment.assignmentId} '
        'taskId=${assignment.taskId ?? "-"} '
        'taskType=${assignment.taskType}',
      );

      lastPortalTaskId = assignment.taskId ?? assignment.assignmentId;
      lastAssignmentId = assignment.assignmentId;
      executionStatus = ExecutionStatus(
        phase: ExecutionPhase.preparing,
        detail:
            'Portal task ${assignment.taskId ?? assignment.assignmentId} received',
        taskType: assignment.taskType,
        assignmentId: assignment.assignmentId,
        taskId: assignment.taskId,
      );
      notifyListeners();

      _logTask(
        'Task ${assignment.taskId ?? assignment.assignmentId} '
        '(${assignment.taskType})',
      );

      if (!isGemmaReady && await _assignmentNeedsLlm(assignment)) {
        _logTask(
          'LLM model not ready after poll - '
          'attempting bundled install before execution',
        );

        await _installBundledAssetIfConfigured();

        if (!isGemmaReady) {
          await downloadGemmaModel();
        }

        if (!isGemmaReady) {
          lastPortalTaskId = assignment.taskId;

          lastAssignmentId = assignment.assignmentId;

          executionStatus = ExecutionStatus(
            phase: ExecutionPhase.preparing,
            detail:
                'Task '
                '${assignment.taskId ?? assignment.assignmentId} '
                'received. Install '
                '${WorkerModelCatalog.displayName} '
                'to run ${assignment.taskType}.',
            taskType: assignment.taskType,
            assignmentId: assignment.assignmentId,
            taskId: assignment.taskId,
          );

          _logTask(
            'LLM model not ready - '
            'open Models tab to finish '
            '${WorkerModelCatalog.displayName} setup',
          );

          lastSync = _formatNow();

          notifyListeners();

          return;
        }
      }

      if (await _assignmentNeedsOcr(assignment) && !ocrModelsReady) {
        if (WorkerOcrBackendPolicy.usePaddleOcr) {
          ocrModelsReady = await PaddleOcrModelInstaller.verifyOnDevice(
            log: _logTask,
          );
          if (!ocrModelsReady && !usesDevMockInference) {
            _logTask(
              'OCR models not on device - '
              'sideload with '
              'tools/push_paddleocr_models_to_device.ps1',
            );
          }
        } else {
          ocrModelsReady = isGemmaReady;
        }
      }

      lastPortalTaskId = assignment.taskId;

      lastAssignmentId = assignment.assignmentId;

      _devMockAdapter?.setTaskTypeHint(assignment.taskType);

      final accepted = await _coordinator.acceptPolledAssignment(assignment);
      if (accepted == null) {
        _logTask('Duplicate assignment delivery ignored');
        return;
      }

      await _coordinator.executeAssignment(accepted);

      final uploadAccepted = await _uploadAssignmentOutput(assignment);

      if (uploadAccepted && executionStatus.phase == ExecutionPhase.completed) {
        tasksProcessed++;
      }

      _logTask(
        'Assignment finished: '
        'phase=${executionStatus.phase} '
        'detail=${executionStatus.detail ?? "(none)"}',
      );

      lastSync = _formatNow();
    } catch (error, stackTrace) {
      _logError('Assignment run failed', error, stackTrace);

      modelError = '$error';

      executionStatus = ExecutionStatus(
        phase: ExecutionPhase.failed,
        detail: '$error',
        taskType: executionStatus.taskType,
        assignmentId: executionStatus.assignmentId,
      );

      lastSync = _formatNow();
    }

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Local demo
  // ---------------------------------------------------------------------------

  Future<void> _runLocalDemoTask() async {
    _logTask(
      'Local demo task - '
      'preparing on-device inference',
    );

    executionStatus = const ExecutionStatus(
      phase: ExecutionPhase.preparing,
      taskType: 'text.generate',
    );

    notifyListeners();

    final input = 'Summarize EdgeMint worker readiness in one sentence.';

    _logTask(
      'Loading adapter for profile '
      '${WorkerModelCatalog.profileId}',
    );

    final adapter = GemmaLiteRtInferenceAdapter();

    final signingMaterial = await _platform.signingMaterial();

    await adapter.loadVerified(
      ModelArtifact(
        modelVersionId: WorkerModelCatalog.modelVersionId,
        digestSha256: WorkerModelCatalog.installedDigestMarker,
        signatureSha256: WorkerModelCatalog.installedAttestationSignature(
          signingMaterial,
        ),
        backend: InferenceBackend.liteRt,
        bytes: Uint8List.fromList([0]),
      ),
      signingKey: signingMaterial,
    );

    executionStatus = executionStatus.copyWith(
      phase: ExecutionPhase.running,
      progressMilli: 0,
    );

    _logTask(
      'Running inference '
      '(input length=${input.length})',
    );

    notifyListeners();

    final output = await adapter.run(
      inputBytes: Uint8List.fromList(utf8.encode(input)),
      resumedState: null,
      onProgress: (progress) async {
        if (progress == 0 || progress >= 500 || progress == 1000) {
          _logTask(
            'Inference progress: '
            '${(progress / 10).toStringAsFixed(0)}%',
          );
        }

        executionStatus = executionStatus.copyWith(progressMilli: progress);

        notifyListeners();
      },
    );

    await adapter.dispose();

    final resultPreview = utf8.decode(output.resultBytes);

    _logTask(
      'Local demo completed '
      '(${resultPreview.length} chars): '
      '${resultPreview.length > 120 ? "${resultPreview.substring(0, 120)}..." : resultPreview}',
    );

    executionStatus = ExecutionStatus(
      phase: ExecutionPhase.completed,
      progressMilli: 1000,
      detail: resultPreview,
      taskType: 'text.generate',
    );

    lastSync = _formatNow();

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _formatNow() =>
      '${DateTime.now().hour.toString().padLeft(2, '0')}:'
      '${DateTime.now().minute.toString().padLeft(2, '0')}';

  Uri _resolveDevServiceUrl(String url) {
    return WorkerConfig.resolveDevServiceUrl(
      workerGatewayBaseUrl: _config.baseUrl,
      embeddedServiceUrl: url,
    );
  }

  // ---------------------------------------------------------------------------
  // Assignment input
  // ---------------------------------------------------------------------------

  Future<AssignmentInputBundle> _loadAssignmentInput(
    WorkerAssignment assignment,
  ) async {
    final manifestUrl = _resolveDevServiceUrl(
      assignment.inputManifestUrl,
    ).replace(queryParameters: {'taskType': assignment.taskType});

    _logTask(
      '[INPUT MANIFEST] '
      'assignmentId=${assignment.assignmentId} '
      'taskType=${assignment.taskType} '
      'url=$manifestUrl',
    );

    final headers = <String, String>{};
    final token = _accessTokenProvider.current;
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await _http
        .get(manifestUrl, headers: headers)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw StateError(
        'Input manifest unavailable '
        '(HTTP ${response.statusCode}) '
        'for ${assignment.taskId}',
      );
    }

    final manifest = jsonDecode(response.body) as Map<String, dynamic>;

    final prompt =
        manifest['prompt'] as String? ??
        'Process ${assignment.taskType} task '
            '${assignment.taskId ?? assignment.assignmentId}';

    _logTask(
      '[TASK INPUT] '
      'assignmentId=${assignment.assignmentId} '
      'taskType=${assignment.taskType} '
      'promptChars=${prompt.length}',
    );

    if (kDebugMode || _verboseTaskLogs) {
      _logTask('[TASK PROMPT] ${_preview(prompt)}');
    }

    final inputText = manifest['inputText'] as String?;
    final contentText = manifest['contentText'] as String?;
    final instructions = manifest['instructions'] as String?;
    final options = manifest['options'] as Map<String, dynamic>?;
    final summarizeOptions = options?['summarize'];
    WorkerContentDiagnostics.logText(
      label: 'TASK MANIFEST PROMPT (preview only, not inference input)',
      content: prompt,
      metadata: {
        'taskId': assignment.taskId ?? assignment.assignmentId,
        'assignmentId': assignment.assignmentId,
        'taskType': assignment.taskType,
      },
    );
    WorkerContentDiagnostics.logText(
      label: 'TASK SOURCE inputText',
      content: inputText ?? contentText,
      metadata: {
        'taskId': assignment.taskId ?? assignment.assignmentId,
        'assignmentId': assignment.assignmentId,
      },
    );
    WorkerContentDiagnostics.logText(
      label: 'TASK INSTRUCTIONS',
      content: instructions,
      metadata: {
        'taskId': assignment.taskId ?? assignment.assignmentId,
        'assignmentId': assignment.assignmentId,
      },
    );
    if (summarizeOptions != null) {
      WorkerContentDiagnostics.logText(
        label: 'TASK OPTIONS summarize',
        content: jsonEncode(summarizeOptions),
        metadata: {
          'taskId': assignment.taskId ?? assignment.assignmentId,
          'assignmentId': assignment.assignmentId,
        },
      );
    }

    final contentUrl = manifest['inputContentUrl'] as String?;

    final Uint8List inputBytes;
    Uint8List? compareImageBytes;
    final bool isImageInput;

    if (contentUrl != null && contentUrl.isNotEmpty) {
      final resolvedContentUrl = _resolveDevServiceUrl(contentUrl);

      _logTask(
        '[TASK CONTENT] '
        'downloading=$resolvedContentUrl',
      );

      final mediaResponse = await _http
          .get(resolvedContentUrl)
          .timeout(const Duration(seconds: 30));

      if (mediaResponse.statusCode != 200) {
        throw StateError(
          'Input content unavailable '
          '(HTTP ${mediaResponse.statusCode})',
        );
      }

      inputBytes = mediaResponse.bodyBytes;

      isImageInput = true;

      _logTask(
        '[TASK CONTENT] '
        'loadedBytes=${inputBytes.length}',
      );

      final compareContentUrl = manifest['compareInputContentUrl'] as String?;
      if (compareContentUrl != null && compareContentUrl.isNotEmpty) {
        final resolvedCompareUrl = _resolveDevServiceUrl(compareContentUrl);

        _logTask(
          '[TASK COMPARE CONTENT] '
          'downloading=$resolvedCompareUrl',
        );

        final compareResponse = await _http
            .get(resolvedCompareUrl)
            .timeout(const Duration(seconds: 30));

        if (compareResponse.statusCode != 200) {
          throw StateError(
            'Compare input unavailable '
            '(HTTP ${compareResponse.statusCode})',
          );
        }

        compareImageBytes = compareResponse.bodyBytes;

        _logTask(
          '[TASK COMPARE CONTENT] '
          'loadedBytes=${compareImageBytes.length}',
        );
      }
    } else {
      inputBytes = Uint8List.fromList(utf8.encode(prompt));

      isImageInput = false;

      _logTask(
        '[TASK TEXT] '
        'utf8Bytes=${inputBytes.length}',
      );
    }

    final signingMaterial = await _platform.signingMaterial();

    return AssignmentInputBundle(
      inputBytes: inputBytes,
      compareImageBytes: compareImageBytes,
      inputDigest: sha256Hex(inputBytes),
      manifest: manifest,
      isImageInput: isImageInput,
      modelArtifact: ModelArtifact(
        modelVersionId: WorkerModelCatalog.modelVersionId,
        digestSha256: WorkerModelCatalog.installedDigestMarker,
        signatureSha256: WorkerModelCatalog.installedAttestationSignature(
          signingMaterial,
        ),
        backend: InferenceBackend.liteRt,
        bytes: Uint8List.fromList([0]),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Assignment output
  // ---------------------------------------------------------------------------

  Future<bool> _uploadAssignmentOutput(WorkerAssignment assignment) async {
    if (executionStatus.phase != ExecutionPhase.completed) {
      return false;
    }

    final assignmentId = assignment.assignmentId;
    if (_outputUploadCoordinator.statusFor(assignmentId) ==
        AssignmentOutputUploadStatus.accepted) {
      return true;
    }
    if (_outputUploadCoordinator.shouldSkipUpload(assignmentId)) {
      _logTask(
        'Output upload skipped (${_outputUploadCoordinator.statusFor(assignmentId).name}): '
        '$assignmentId',
      );
      return false;
    }
    if (!_outputUploadCoordinator.markInFlight(assignmentId)) {
      _logTask('Output upload skipped (concurrent): $assignmentId');
      return false;
    }

    final resultText = executionStatus.detail;

    if (resultText == null || resultText.isEmpty) {
      _outputUploadCoordinator.releaseInFlight(assignmentId);
      return false;
    }

    try {
      final uploadUrl = _resolveDevServiceUrl(assignment.outputUploadUrl);

      _logTask(
        'Uploading result to '
        '$uploadUrl',
      );

      final lastOutput = _inference.lastOutput;

      final pipelineResult = _taskEngine.lastResult;

      final metrics = <String, dynamic>{
        'taskType': assignment.taskType,
        'taskId': assignment.taskId,
        'assignmentId': assignment.assignmentId,
      };

      if (pipelineResult != null) {
        metrics['structuredResultJson'] = jsonEncode(pipelineResult.toJson());
        final transcript = pipelineResult.output?['modelTranscript'];
        if (transcript is String && transcript.trim().isNotEmpty) {
          metrics['modelTranscript'] = transcript.trim();
        }
      }

      final payload = <String, dynamic>{
        'resultText': resultText,
        'metrics': metrics,
      };

      if (lastOutput != null && lastOutput.metrics['outputKind'] == 'image') {
        payload['resultFileBase64'] = base64Encode(lastOutput.resultBytes);

        payload['resultFileName'] = 'result.png';

        payload['resultMimeType'] =
            lastOutput.metrics['outputMimeType'] ?? 'image/png';

        _logTask(
          'Including image result '
          '(${lastOutput.resultBytes.length} bytes)',
        );
      }

      _logTask(
        '[OUTPUT UPLOAD] '
        'taskId=${assignment.taskId ?? "-"} '
        'assignmentId=${assignment.assignmentId} '
        'chars=${resultText.length} '
        'result="${_preview(resultText)}"',
      );

      final encodedPayload = jsonEncode(payload);
      for (
        var attempt = 0;
        attempt < _outputUploadCoordinator.maxAttempts;
        attempt += 1
      ) {
        try {
          final response = await _http
              .post(
                uploadUrl,
                headers: const {'Content-Type': 'application/json'},
                body: encodedPayload,
              )
              .timeout(const Duration(seconds: 15));

          _logTask(
            '[OUTPUT RESPONSE] '
            'status=${response.statusCode} '
            'taskId=${assignment.taskId ?? "-"} '
            'attempt=${attempt + 1}',
          );

          if (kDebugMode || _verboseTaskLogs) {
            _logTask(
              '[OUTPUT RESPONSE BODY] '
              '${_preview(response.body)}',
            );
          }

          if (response.statusCode >= 200 && response.statusCode < 300) {
            _outputUploadCoordinator.markAccepted(assignmentId);
            _logTask(
              'Portal task '
              '${assignment.taskId ?? "?"} '
              'marked completed',
            );
            return true;
          }

          if (_outputUploadCoordinator.isTerminalHttpStatus(
            response.statusCode,
          )) {
            _outputUploadCoordinator.markRejectedTerminal(assignmentId);
            executionStatus = executionStatus.copyWith(
              phase: ExecutionPhase.failed,
              detail:
                  'Portal rejected output: '
                  '${_preview(response.body, maxLength: 240)}',
            );
            notifyListeners();
            return false;
          }

          if (_outputUploadCoordinator.isRetryableHttpStatus(
                response.statusCode,
              ) &&
              attempt + 1 < _outputUploadCoordinator.maxAttempts) {
            _logTask(
              'Output upload retryable HTTP ${response.statusCode}; '
              'retry ${attempt + 2}/${_outputUploadCoordinator.maxAttempts}',
            );
            await Future<void>.delayed(
              _outputUploadCoordinator.backoffForAttempt(attempt),
            );
            continue;
          }

          _logTask('Output upload HTTP ${response.statusCode}');
          _outputUploadCoordinator.releaseInFlight(assignmentId);
          return false;
        } on TimeoutException catch (error, stackTrace) {
          if (attempt + 1 < _outputUploadCoordinator.maxAttempts) {
            _logTask(
              'Output upload timeout; '
              'retry ${attempt + 2}/${_outputUploadCoordinator.maxAttempts}',
            );
            await Future<void>.delayed(
              _outputUploadCoordinator.backoffForAttempt(attempt),
            );
            continue;
          }
          _logError('Output upload timed out', error, stackTrace);
          _outputUploadCoordinator.releaseInFlight(assignmentId);
          return false;
        }
      }

      _outputUploadCoordinator.releaseInFlight(assignmentId);
      return false;
    } catch (error, stackTrace) {
      _logError('Output upload failed', error, stackTrace);
      _outputUploadCoordinator.releaseInFlight(assignmentId);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Execution status
  // ---------------------------------------------------------------------------

  void _onExecutionStatus(ExecutionStatus status) {
    executionStatus = status;

    _logTask(
      'Execution status: '
      'phase=${status.phase} '
      'task=${status.taskType ?? "-"} '
      'progress=${status.progressMilli}',
    );

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  void handleAppLifecycleState(AppLifecycleState state) {
    _processLifecycle.handleAppLifecycleState(state);
  }

  Map<String, Object?> get processLifecycleTelemetry =>
      _processLifecycle.toTelemetry();

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _disposed = true;

    stopAutoAssignmentLoop();

    unawaited(
      _processLifecycle.markProcessTerminated(reason: 'controller_disposed'),
    );

    _api.close();

    _http.close();

    super.dispose();
  }
}
