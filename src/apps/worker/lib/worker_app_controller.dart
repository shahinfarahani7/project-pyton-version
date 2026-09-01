import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:http/http.dart' as http;

import 'api/worker_api_client.dart';
import 'api/worker_assignment_models.dart';
import 'config/worker_config.dart';
import 'inference/llm/qwen_task_processor.dart';
import 'inference/ocr/fake_ocr_engine.dart';
import 'inference/ocr/ocr_engine.dart';
import 'inference/ocr/paddle_ocr_engine.dart';
import 'inference/ocr/paddle_ocr_installer.dart';
import 'models/worker_model_catalog.dart';
import 'platform/worker_runtime_channel.dart';
import 'runtime/assignment_coordinator.dart';
import 'runtime/dev_mock_inference_adapter.dart';
import 'runtime/device_snapshot.dart';
import 'runtime/encrypted_store.dart';
import 'runtime/execution_status.dart';
import 'runtime/gemma_bootstrap.dart';
import 'runtime/gemma_inference_adapter.dart';
import 'runtime/inference_adapter.dart';
import 'runtime/switchable_inference_adapter.dart';
import 'runtime/worker_model_installer.dart';
import 'tasks/task_execution_engine.dart';
import 'tasks/task_type_mapper.dart';

enum ModelInstallPhase { idle, downloading, ready, failed }

class WorkerAppController extends ChangeNotifier {
  WorkerAppController({
    WorkerConfig? config,
    http.Client? httpClient,
    WorkerRuntimeChannel? platform,
    OcrEngine? ocrEngine,
    QwenTaskProcessor? qwenProcessor,
    TaskExecutionEngine? taskEngine,
  }) : _config = config ?? WorkerConfig.fromEnvironment(),
       _http = httpClient ?? http.Client(),
       _platform = platform ?? WorkerRuntimeChannel(),
       _ocrEngineRef = OcrEngineRef(ocrEngine ?? PaddleOcrEngine()) {
    //
    // IMPORTANT:
    //
    // The actual installed model is defined by WorkerModelCatalog.
    //
    // After migrating WorkerModelCatalog to:
    //
    // Qwen2.5-0.5B-Instruct
    // ModelType.qwen
    // ModelFileType.task
    //
    // x86 Android is no longer automatically forced into mock mode.
    //
    _inference = SwitchableInferenceAdapter(GemmaLiteRtInferenceAdapter());

    _qwenProcessor = qwenProcessor ?? QwenTaskProcessor();

    _taskEngine =
        taskEngine ??
        TaskExecutionEngine(
          ocrEngine: _ocrEngineRef,
          qwenProcessor: _qwenProcessor,
        );

    _api = WorkerApiClient(config: _config, httpClient: _http);

    _coordinator = AssignmentCoordinator(
      api: _api,
      store: InMemoryEncryptedStore(),
      platform: _platform,
      inference: _inference,
      inputLoader: _loadAssignmentInput,
      taskEngine: _taskEngine,
      onStatus: _onExecutionStatus,
    );
  }

  WorkerConfig _config;

  final http.Client _http;
  final WorkerRuntimeChannel _platform;

  late final WorkerApiClient _api;
  late final SwitchableInferenceAdapter _inference;

  final OcrEngineRef _ocrEngineRef;
  Future<bool>? _modelReadyFuture;

  late final QwenTaskProcessor _qwenProcessor;
  late final TaskExecutionEngine _taskEngine;
  late final AssignmentCoordinator _coordinator;

  DevMockInferenceAdapter? _devMockAdapter;

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

  int _assignmentLoopGeneration = 0;

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
      backendOnline && !isGemmaDownloading && available;

  bool get canPollAssignments => canAcceptAssignments;

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

  void _logTask(String message) {
    developer.log(message, name: 'EdgeMintWorker');
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

  void _logError(String message, Object error, [StackTrace? stackTrace]) {
    developer.log(
      '$message: $error',
      name: 'EdgeMintWorker',
      error: error,
      stackTrace: stackTrace,
    );
  }

  // ---------------------------------------------------------------------------
  // Bootstrap
  // ---------------------------------------------------------------------------

  Future<void> bootstrap() async {
    _logTask('Worker bootstrap started');

    await _resolveBackendUrl();

    await _refreshBackendHealth();

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
    _logTask('Auto-assignment loop started');

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
      _logTask('Auto-assignment loop stopped');
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
      // Qwen2.5 .task is allowed to attempt real inference
      // on Android x86/x86_64.
      //
      if (_devMockRequested) {
        _enableDevMockInference();

        _ocrEngineRef.delegate = FakeOcrEngine();

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
          'real ${WorkerModelCatalog.displayName} inference enabled',
        );
      } else {
        _logTask(
          'Android ARM device detected - '
          'real ${WorkerModelCatalog.displayName} inference enabled',
        );
      }

      //
      // Real OCR is independent from the LLM architecture.
      //
      _ocrEngineRef.delegate = PaddleOcrEngine();

      ocrModelsReady = await PaddleOcrModelInstaller.verifyOnDevice(
        log: _logTask,
      );

      if (!ocrModelsReady) {
        _logTask('PaddleOCR models are not installed on device');
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
        final probe = await _http
            .get(WorkerConfig(baseUrl: candidate).resolve('/health/live'))
            .timeout(const Duration(seconds: 5));

        if (probe.statusCode == 200) {
          if (_config.baseUrl != candidate) {
            _logTask(
              'Backend reachable at $candidate '
              '(was ${_config.baseUrl})',
            );

            _config.baseUrl = candidate;

            _api.reconfigure(_config);
          }

          return;
        }
      } catch (_) {
        continue;
      }
    }

    _logTask(
      'No backend candidate responded - tried '
      '${WorkerConfig.connectionCandidates().join(", ")}',
    );
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

  Future<bool> _ensureModelReadyInternal() async {
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
    } catch (error, stackTrace) {
      _logError('Model check failed', error, stackTrace);
    } finally {
      _modelReadyFuture = null;
    }

    return false;
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
    modelPhase = ModelInstallPhase.ready;

    modelProgress = 1;

    modelError = null;
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

        await installer.fromAsset(bundledAsset).install();
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
  }

  Future<void> _clearStaleDownloadTasks({bool forceReinstall = false}) async {
    if (forceReinstall) {
      final possibleModels = <String>{
        WorkerModelCatalog.fileName,
        'Qwen3-0.6B.litertlm',
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
    _logTask('Checking for next assignment');

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
        'Waiting for assignment '
        'from worker-gateway',
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

      _logTask(
        'Task ${assignment.taskId ?? assignment.assignmentId} '
        '(${assignment.taskType})',
      );

      if (!isGemmaReady && await _assignmentNeedsLlm(assignment)) {
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
          'assignment held until '
          '${WorkerModelCatalog.displayName} '
          'is installed',
        );

        lastSync = _formatNow();

        notifyListeners();

        return;
      }

      if (await _assignmentNeedsOcr(assignment) && !ocrModelsReady) {
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
      }

      lastPortalTaskId = assignment.taskId;

      lastAssignmentId = assignment.assignmentId;

      _devMockAdapter?.setTaskTypeHint(assignment.taskType);

      await _coordinator.executeAssignment(assignment);

      await _uploadAssignmentOutput(assignment);

      if (executionStatus.phase == ExecutionPhase.completed) {
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

    await adapter.loadVerified(
      ModelArtifact(
        modelVersionId: WorkerModelCatalog.modelVersionId,
        digestSha256: WorkerModelCatalog.installedDigestMarker,
        signatureSha256: WorkerModelCatalog.installedDigestMarker,
        backend: InferenceBackend.liteRt,
        bytes: Uint8List.fromList([0]),
      ),
      signingKey: await _platform.signingMaterial(),
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
    final parsed = Uri.parse(url);

    if (parsed.host != '127.0.0.1' && parsed.host != 'localhost') {
      return parsed;
    }

    return parsed.replace(host: _config.baseUrl.host, port: 8080);
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

    final response = await _http
        .get(manifestUrl)
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

    if (_verboseTaskLogs) {
      _logTask('[TASK PROMPT] ${_preview(prompt)}');
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

    return AssignmentInputBundle(
      inputBytes: inputBytes,
      compareImageBytes: compareImageBytes,
      inputDigest: sha256Hex(inputBytes),
      manifest: manifest,
      isImageInput: isImageInput,
      modelArtifact: ModelArtifact(
        modelVersionId: WorkerModelCatalog.modelVersionId,
        digestSha256: WorkerModelCatalog.installedDigestMarker,
        signatureSha256: WorkerModelCatalog.installedDigestMarker,
        backend: InferenceBackend.liteRt,
        bytes: Uint8List.fromList([0]),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Assignment output
  // ---------------------------------------------------------------------------

  Future<void> _uploadAssignmentOutput(WorkerAssignment assignment) async {
    if (executionStatus.phase != ExecutionPhase.completed) {
      return;
    }

    final resultText = executionStatus.detail;

    if (resultText == null || resultText.isEmpty) {
      return;
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
        'chars=${resultText.length}',
      );

      final response = await _http
          .post(
            uploadUrl,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      _logTask(
        '[OUTPUT RESPONSE] '
        'status=${response.statusCode} '
        'taskId=${assignment.taskId ?? "-"}',
      );

      if (_verboseTaskLogs) {
        _logTask(
          '[OUTPUT RESPONSE BODY] '
          '${_preview(response.body)}',
        );
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _logTask(
          'Portal task '
          '${assignment.taskId ?? "?"} '
          'marked completed',
        );
      } else {
        _logTask(
          'Output upload HTTP '
          '${response.statusCode}',
        );
      }
    } catch (error, stackTrace) {
      _logError('Output upload failed', error, stackTrace);
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
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _disposed = true;

    stopAutoAssignmentLoop();

    _api.close();

    _http.close();

    super.dispose();
  }
}
