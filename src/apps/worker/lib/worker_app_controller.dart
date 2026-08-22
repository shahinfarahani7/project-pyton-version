import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:http/http.dart' as http;

import 'api/worker_api_client.dart';
import 'api/worker_assignment_models.dart';
import 'config/worker_config.dart';
import 'dart:developer' as developer;
import 'models/worker_model_catalog.dart';
import 'platform/worker_runtime_channel.dart';
import 'runtime/assignment_coordinator.dart';
import 'runtime/dev_mock_inference_adapter.dart';
import 'runtime/encrypted_store.dart';
import 'runtime/device_snapshot.dart';
import 'runtime/execution_status.dart';
import 'runtime/gemma_bootstrap.dart';
import 'runtime/gemma_inference_adapter.dart';
import 'runtime/worker_model_installer.dart';
import 'runtime/inference_adapter.dart';
import 'runtime/switchable_inference_adapter.dart';
import 'inference/llm/qwen_task_processor.dart';
import 'inference/ocr/fake_ocr_engine.dart';
import 'inference/ocr/ocr_engine.dart';
import 'inference/ocr/paddle_ocr_engine.dart';
import 'inference/ocr/paddle_ocr_installer.dart';
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
  })  : _config = config ?? WorkerConfig.fromEnvironment(),
        _http = httpClient ?? http.Client(),
        _platform = platform ?? WorkerRuntimeChannel(),
        _ocrEngineRef = OcrEngineRef(ocrEngine ?? PaddleOcrEngine()) {
    _inference = SwitchableInferenceAdapter(GemmaLiteRtInferenceAdapter());
    _qwenProcessor = qwenProcessor ?? QwenTaskProcessor();
    _taskEngine = taskEngine ??
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
  late final QwenTaskProcessor _qwenProcessor;
  late final TaskExecutionEngine _taskEngine;
  late final AssignmentCoordinator _coordinator;
  DevMockInferenceAdapter? _devMockAdapter;

  bool available = true;
  bool backendOnline = false;
  String backendMessage = 'Checking backend…';
  ModelInstallPhase modelPhase = ModelInstallPhase.idle;
  double modelProgress = 0;
  String? modelError;
  ExecutionStatus executionStatus = const ExecutionStatus(phase: ExecutionPhase.idle);
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

  static const _assignmentPollInterval = Duration(seconds: 2);
  static const _assignmentLongPollSeconds = 20;

  int _assignmentLoopGeneration = 0;
  bool _disposed = false;
  bool _processingAssignment = false;

  bool get isAutoAssigning => available && backendOnline && !_disposed;

  void _logTask(String message) {
    developer.log(message, name: 'EdgeMintWorker');
  }

  void _logError(String message, Object error, [StackTrace? stackTrace]) {
    developer.log('$message: $error', name: 'EdgeMintWorker', error: error, stackTrace: stackTrace);
  }

  Future<void> bootstrap() async {
    await _resolveBackendUrl();
    await _refreshBackendHealth();
    await _refreshDeviceReadiness();
    try {
      await ensureModelReady();
    } catch (error) {
      _logTask('Model check failed: $error');
      if (!usesDevMockInference && modelPhase != ModelInstallPhase.downloading) {
        modelPhase = ModelInstallPhase.idle;
      }
    }
    notifyListeners();
    if (available) {
      startAutoAssignmentLoop();
    }
  }

  void setAvailable(bool value) {
    if (available == value) {
      return;
    }
    available = value;
    if (value) {
      _logTask('Worker availability on — listening for assignments');
      startAutoAssignmentLoop();
    } else {
      _logTask('Worker availability off — auto-assignment paused');
      stopAutoAssignmentLoop();
      if (executionStatus.phase == ExecutionPhase.waitingForAssignment) {
        executionStatus = const ExecutionStatus(phase: ExecutionPhase.idle);
      }
    }
    notifyListeners();
  }

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

  bool get _isBusyExecuting => switch (executionStatus.phase) {
        ExecutionPhase.preparing ||
        ExecutionPhase.running ||
        ExecutionPhase.checkpointing ||
        ExecutionPhase.submitting ||
        ExecutionPhase.cleaningUp => true,
        _ => false,
      };

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
        _logTask('Emulator detected — battery treated as AC power for dev');
      }
      if (isX86Android) {
        const forceReal = bool.fromEnvironment(
          'WORKER_FORCE_REAL_INFERENCE',
          defaultValue: false,
        );
        if (forceReal) {
          _logTask(
            'x86 emulator but WORKER_FORCE_REAL_INFERENCE=true — attempting real Qwen3 LiteRT '
            '(requires arm64-v8a native libs; enable ARM mode in MEmu 9.2+ settings)',
          );
        } else {
          _enableDevMockInference();
          _ocrEngineRef.delegate = FakeOcrEngine();
          ocrModelsReady = true;
        }
      } else {
        ocrModelsReady = await PaddleOcrModelInstaller.verifyOnDevice(log: _logTask);
      }
    } catch (error) {
      _logTask('Device readiness probe failed: $error');
    }
  }

  String get batteryLabel {
    if (isEmulator) {
      return isCharging ? '$batteryPercent% (emulator AC)' : '$batteryPercent% (emulator)';
    }
    return isCharging ? '$batteryPercent% (charging)' : '$batteryPercent%';
  }

  String get storageLabel {
    if (freeStorageMb >= 1024) {
      return '${(freeStorageMb / 1024).toStringAsFixed(1)} GB free';
    }
    return '$freeStorageMb MB free';
  }

  Future<void> refreshBackendHealth() async {
    await _resolveBackendUrl();
    await _refreshBackendHealth();
    notifyListeners();
  }

  Future<void> _resolveBackendUrl() async {
    for (final candidate in WorkerConfig.connectionCandidates()) {
      try {
        final probe = await _http
            .get(
              WorkerConfig(baseUrl: candidate).resolve('/health/live'),
            )
            .timeout(const Duration(seconds: 5));
        if (probe.statusCode == 200) {
          if (_config.baseUrl != candidate) {
            _logTask('Backend reachable at $candidate (was ${_config.baseUrl})');
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
      'No backend candidate responded — tried ${WorkerConfig.connectionCandidates().join(", ")}',
    );
  }

  Future<void> _refreshBackendHealth() async {
    try {
      final response = await _http
          .get(_config.resolve('/health/live'))
          .timeout(_config.requestTimeout);
      backendOnline = response.statusCode == 200;
      backendMessage = backendOnline
          ? 'Connected (${_config.baseUrl.host}:${_config.baseUrl.port})'
          : 'Unreachable (${_config.baseUrl.host}:${_config.baseUrl.port}). '
              'Open port 8081 in Windows Firewall and ensure the phone is on the same LAN.';
    } catch (error) {
      backendOnline = false;
      final hint = _config.baseUrl.host == '127.0.0.1'
          ? 'Run on PC: powershell -File tools/start_worker_dev.ps1'
          : 'Run tools/open_worker_gateway_firewall.ps1 as Administrator on the PC.';
      backendMessage =
          'Unreachable (${_config.baseUrl.host}:${_config.baseUrl.port}): $error. $hint';
    }
    lastSync = _formatNow();
  }

  Future<bool> ensureModelReady() async {
    if (usesDevMockInference) {
      _setModelReady();
      return true;
    }
    try {
      if (await WorkerModelInstaller.verifyActive(log: _logTask)) {
        _setModelReady();
        return true;
      }
      final ready = await WorkerModelInstaller.ensureReady(log: _logTask);
      if (ready) {
        _setModelReady();
        return true;
      }
    } catch (error) {
      _logTask('Model inventory check failed: $error');
      return false;
    }
    if (modelPhase != ModelInstallPhase.downloading) {
      modelPhase = ModelInstallPhase.failed;
      modelError = 'Model files present but inference is not active. Tap Prepare Qwen3 again or sideload the model.';
    }
    return false;
  }

  Future<bool> _verifyAndMarkModelReady() async {
    if (await WorkerModelInstaller.verifyActive(log: _logTask)) {
      _setModelReady();
      return true;
    }
    if (await WorkerModelInstaller.ensureReady(log: _logTask)) {
      _setModelReady();
      return true;
    }
    return false;
  }

  Future<void> _clearBrokenModelInstall() async {
    await _clearStaleDownloadTasks(forceReinstall: true);
    for (final modelId in ['artifact', WorkerModelCatalog.fileName]) {
      try {
        await FlutterGemma.uninstallModel(modelId);
      } catch (_) {}
    }
    try {
      await FlutterGemma.clearActiveInferenceIdentity();
    } catch (_) {}
  }

  void _enableDevMockInference() {
    usesDevMockInference = true;
    _devMockAdapter = DevMockInferenceAdapter();
    _inference.use(_devMockAdapter!);
    _setModelReady();
    _logTask(
      'x86 emulator detected — Qwen3 .litertlm needs ARM64. '
      'Using dev mock inference so portal tasks still run.',
    );
  }

  void _setModelReady() {
    modelPhase = ModelInstallPhase.ready;
    modelProgress = 1;
    modelError = null;
  }

  Future<void> _refreshModelState() async {
    await ensureModelReady();
  }

  Future<void> downloadGemmaModel() async {
    if (usesDevMockInference) {
      _logTask('Dev mock already active on x86 emulator — no Qwen3 download needed');
      _setModelReady();
      notifyListeners();
      return;
    }
    if (modelPhase == ModelInstallPhase.downloading) {
      return;
    }

    if (await _verifyAndMarkModelReady()) {
      _logTask('Qwen3 model already active — skipping download');
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
      await _clearBrokenModelInstall();
      final bundledAsset = WorkerModelCatalog.bundledAssetFromEnvironment();
      var downloadUrl = WorkerModelCatalog.resolveDownloadUrl(_config.baseUrl);
      if (bundledAsset == null && WorkerModelCatalog.usesBackendArtifactProxy()) {
        if (backendOnline) {
          _logTask('Using backend model proxy: $downloadUrl');
        } else {
          downloadUrl = WorkerModelCatalog.huggingFaceDownloadUrl;
          _logTask('Backend offline — using direct Hugging Face: $downloadUrl');
        }
      } else {
        _logTask('Model download URL: $downloadUrl');
      }
      final installer = WorkerModelCatalog.installBuilder();
      if (bundledAsset != null) {
        await installer.fromAsset(bundledAsset).install();
      } else {
        await _installFromNetworkWithFallback(installer, downloadUrl);
      }
      if (!await _verifyAndMarkModelReady()) {
        throw StateError(
          'Download finished but Qwen3 could not be activated. '
          'Try sideload: tools/push_qwen_model_to_emulator.ps1',
        );
      }
      _logTask('Qwen3 install verified — ready for inference');
    } catch (error, stackTrace) {
      _logError('Model download failed', error, stackTrace);
      modelPhase = ModelInstallPhase.failed;
      modelError = '$error';
      _logTask('Model download failed: $error');
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
        'Primary download failed ($primaryError) — retrying via Hugging Face',
      );
      await _clearStaleDownloadTasks(forceReinstall: true);
      await _installFromNetwork(installer, fallbackUrl);
    }
  }

  Future<void> _installFromNetwork(
    InferenceInstallationBuilder installer,
    String downloadUrl,
  ) async {
    _logTask('Starting network install: $downloadUrl');
    await installer
        .fromNetwork(downloadUrl, foreground: true)
        .withProgress((progress) {
          modelProgress = progress / 100.0;
          notifyListeners();
        })
        .install();
  }

  Future<void> _clearStaleDownloadTasks({bool forceReinstall = false}) async {
    if (forceReinstall) {
      try {
        await FlutterGemma.uninstallModel(WorkerModelCatalog.fileName);
      } catch (_) {}
    }
    try {
      await FileDownloader().reset(group: 'smart_downloads');
      if (forceReinstall) {
        _logTask('Cleared partial model install before retry');
      }
    } catch (error) {
      _logTask('Could not reset download tasks: $error');
    }
  }

  bool get isGemmaReady => modelPhase == ModelInstallPhase.ready;

  bool get isGemmaDownloading => modelPhase == ModelInstallPhase.downloading;

  bool get canStartGemmaDownload => modelPhase != ModelInstallPhase.downloading;

  /// Direct URL for browser download (backend proxy or Hugging Face fallback).
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

  bool get canAcceptAssignments =>
      backendOnline && !isGemmaDownloading && available;

  bool get canPollAssignments => canAcceptAssignments;

  bool get requiresHuggingFaceToken => false;

  String get gemmaDownloadLabel => switch (modelPhase) {
        ModelInstallPhase.idle => usesDevMockInference
            ? 'Dev mock ready (x86 emulator)'
            : 'Prepare ${WorkerModelCatalog.displayName}',
        ModelInstallPhase.downloading =>
          'Downloading ${WorkerModelCatalog.displayName}… ${(modelProgress * 100).toStringAsFixed(0)}%',
        ModelInstallPhase.ready => usesDevMockInference
            ? 'Dev mock ready (x86 — use ARM phone for real Qwen3)'
            : '${WorkerModelCatalog.displayName} installed',
        ModelInstallPhase.failed => 'Retry model download',
      };

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
    _logTask('Worker base URL: ${_config.baseUrl}');
    _logTask(
      'Pre-checks: available=$available, modelPhase=$modelPhase, modelReady=$isGemmaReady',
    );

    try {
      await _refreshBackendHealth();
      await _refreshDeviceReadiness();
      _logTask(
        'Device: battery=$batteryLabel emulator=$isEmulator',
      );
      _logTask(
        'Backend health: online=$backendOnline message="$backendMessage"',
      );
      if (!backendOnline) {
        _logTask('Aborting — backend offline');
        return;
      }
      if (!available) {
        _logTask('Aborting — worker availability is off');
        return;
      }

      await ensureModelReady();
      _logTask(
        'Model check after ensureModelReady: phase=$modelPhase ready=$isGemmaReady',
      );

      _logTask('Waiting for assignment from worker-gateway…');
      final assignment = await _coordinator.pollAssignment(waitSeconds: waitSeconds);
      if (assignment == null) {
        _logTask('No tasks in queue');
        if (announceEmptyQueue) {
          executionStatus = const ExecutionStatus(
            phase: ExecutionPhase.idle,
            detail: 'No tasks in queue. Create a task in the customer portal first.',
          );
          lastSync = _formatNow();
          notifyListeners();
        }
        return;
      }

      _logTask(
        'Task ${assignment.taskId ?? assignment.assignmentId} (${assignment.taskType})',
      );

      if (!isGemmaReady && await _assignmentNeedsLlm(assignment)) {
        lastPortalTaskId = assignment.taskId;
        lastAssignmentId = assignment.assignmentId;
        executionStatus = ExecutionStatus(
          phase: ExecutionPhase.preparing,
          detail:
              'Task ${assignment.taskId ?? assignment.assignmentId} received. '
              'Install Qwen3 on Home to run ${assignment.taskType}.',
          taskType: assignment.taskType,
          assignmentId: assignment.assignmentId,
          taskId: assignment.taskId,
        );
        _logTask('Model not ready — assignment held until Qwen3 is installed');
        lastSync = _formatNow();
        notifyListeners();
        return;
      }

      if (await _assignmentNeedsOcr(assignment) && !ocrModelsReady) {
        ocrModelsReady = await PaddleOcrModelInstaller.verifyOnDevice(log: _logTask);
        if (!ocrModelsReady && !usesDevMockInference) {
          _logTask(
            'OCR models not on device — sideload with tools/push_paddleocr_models_to_device.ps1',
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
        'Assignment finished: phase=${executionStatus.phase} detail=${executionStatus.detail ?? "(none)"}',
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

  Future<void> _runLocalDemoTask() async {
    _logTask('Local demo task — preparing on-device inference');
    executionStatus = const ExecutionStatus(
      phase: ExecutionPhase.preparing,
      taskType: 'text.generate',
    );
    notifyListeners();

    final input = 'Summarize EdgeMint worker readiness in one sentence.';
    _logTask('Loading adapter for profile ${WorkerModelCatalog.profileId}');
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
    executionStatus = executionStatus.copyWith(phase: ExecutionPhase.running, progressMilli: 0);
    _logTask('Running inference (input length=${input.length})');
    notifyListeners();
    final output = await adapter.run(
      inputBytes: Uint8List.fromList(utf8.encode(input)),
      resumedState: null,
      onProgress: (progress) async {
        if (progress == 0 || progress >= 500 || progress == 1000) {
          _logTask('Inference progress: ${(progress / 10).toStringAsFixed(0)}%');
        }
        executionStatus = executionStatus.copyWith(progressMilli: progress);
        notifyListeners();
      },
    );
    await adapter.dispose();
    final resultPreview = utf8.decode(output.resultBytes);
    _logTask(
      'Local demo completed (${resultPreview.length} chars): ${resultPreview.length > 120 ? "${resultPreview.substring(0, 120)}…" : resultPreview}',
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

  String _formatNow() => '${DateTime.now().hour.toString().padLeft(2, '0')}:'
      '${DateTime.now().minute.toString().padLeft(2, '0')}';

  Uri _resolveDevServiceUrl(String url) {
    final parsed = Uri.parse(url);
    if (parsed.host != '127.0.0.1' && parsed.host != 'localhost') {
      return parsed;
    }
    return parsed.replace(host: _config.baseUrl.host, port: 8080);
  }

  Future<AssignmentInputBundle> _loadAssignmentInput(WorkerAssignment assignment) async {
    final manifestUrl = _resolveDevServiceUrl(assignment.inputManifestUrl).replace(
      queryParameters: {'taskType': assignment.taskType},
    );
    _logTask('Loading input manifest: $manifestUrl');
    final response = await _http
        .get(manifestUrl)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError(
        'Input manifest unavailable (HTTP ${response.statusCode}) for ${assignment.taskId}',
      );
    }
    final manifest = jsonDecode(response.body) as Map<String, dynamic>;
    final prompt = manifest['prompt'] as String? ??
        'Process ${assignment.taskType} task ${assignment.taskId ?? assignment.assignmentId}';
    final contentUrl = manifest['inputContentUrl'] as String?;
    final Uint8List inputBytes;
    final bool isImageInput;
    if (contentUrl != null) {
      final mediaResponse =
          await _http.get(_resolveDevServiceUrl(contentUrl)).timeout(const Duration(seconds: 30));
      if (mediaResponse.statusCode != 200) {
        throw StateError('Input content unavailable (HTTP ${mediaResponse.statusCode})');
      }
      inputBytes = mediaResponse.bodyBytes;
      isImageInput = true;
      _logTask('Input image loaded (${inputBytes.length} bytes) from $contentUrl');
    } else {
      inputBytes = Uint8List.fromList(utf8.encode(prompt));
      isImageInput = false;
      _logTask(
        'Input ready: ${manifest['documentTitle'] ?? assignment.taskType} (${inputBytes.length} bytes)',
      );
    }
    return AssignmentInputBundle(
      inputBytes: inputBytes,
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
      _logTask('Uploading result to $uploadUrl');
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
        payload['resultMimeType'] = lastOutput.metrics['outputMimeType'] ?? 'image/png';
        _logTask('Including image result (${lastOutput.resultBytes.length} bytes)');
      }
      final response = await _http
          .post(
            uploadUrl,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _logTask('Portal task ${assignment.taskId ?? "?"} marked completed');
      } else {
        _logTask('Output upload HTTP ${response.statusCode}');
      }
    } catch (error) {
      _logTask('Output upload failed: $error');
    }
  }

  void _onExecutionStatus(ExecutionStatus status) {
    executionStatus = status;
    _logTask(
      'Execution status: phase=${status.phase} task=${status.taskType ?? "-"} progress=${status.progressMilli}',
    );
  }

  @override
  void dispose() {
    _disposed = true;
    stopAutoAssignmentLoop();
    _api.close();
    _http.close();
    super.dispose();
  }
}
