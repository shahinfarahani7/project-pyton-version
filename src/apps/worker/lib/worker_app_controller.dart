import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:http/http.dart' as http;

import 'api/worker_api_client.dart';
import 'api/worker_assignment_models.dart';
import 'config/worker_config.dart';
import 'debug/worker_task_log.dart';
import 'models/worker_model_catalog.dart';
import 'platform/worker_runtime_channel.dart';
import 'runtime/assignment_coordinator.dart';
import 'runtime/encrypted_store.dart';
import 'runtime/execution_status.dart';
import 'runtime/gemma_bootstrap.dart';
import 'runtime/gemma_inference_adapter.dart';
import 'runtime/inference_adapter.dart';

enum ModelInstallPhase { idle, downloading, ready, failed }

class WorkerAppController extends ChangeNotifier {
  WorkerAppController({
    WorkerConfig? config,
    http.Client? httpClient,
    WorkerRuntimeChannel? platform,
  })  : _config = config ?? WorkerConfig.fromEnvironment(),
        _http = httpClient ?? http.Client(),
        _platform = platform ?? WorkerRuntimeChannel() {
    _api = WorkerApiClient(config: _config, httpClient: _http);
    _coordinator = AssignmentCoordinator(
      api: _api,
      store: InMemoryEncryptedStore(),
      platform: _platform,
      inference: GemmaLiteRtInferenceAdapter(),
      inputLoader: _loadAssignmentInput,
      onStatus: _onExecutionStatus,
    );
  }

  final WorkerConfig _config;
  final http.Client _http;
  final WorkerRuntimeChannel _platform;

  late final WorkerApiClient _api;
  late final AssignmentCoordinator _coordinator;

  bool available = true;
  bool backendOnline = false;
  String backendMessage = 'Checking backend…';
  ModelInstallPhase modelPhase = ModelInstallPhase.idle;
  double modelProgress = 0;
  String? modelError;
  ExecutionStatus executionStatus = const ExecutionStatus(phase: ExecutionPhase.idle);
  String lastSync = 'never';

  List<String> get taskRunLogs => WorkerTaskLog.lines;

  void clearTaskRunLogs() {
    WorkerTaskLog.clear();
    notifyListeners();
  }

  void _logTask(String message) {
    WorkerTaskLog.info(message);
    notifyListeners();
  }

  Future<void> bootstrap() async {
    await _refreshBackendHealth();
    try {
      await GemmaBootstrap.ensureInitialized();
      await _refreshModelState();
    } catch (_) {
      modelPhase = ModelInstallPhase.idle;
    }
    notifyListeners();
  }

  Future<void> refreshBackendHealth() async {
    await _refreshBackendHealth();
    notifyListeners();
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
      backendMessage =
          'Unreachable (${_config.baseUrl.host}:${_config.baseUrl.port}): $error. '
          'Run tools/open_worker_gateway_firewall.ps1 as Administrator on the PC.';
    }
    lastSync = _formatNow();
  }

  Future<void> _refreshModelState() async {
    if (FlutterGemma.hasActiveModel()) {
      modelPhase = ModelInstallPhase.ready;
      modelProgress = 1;
      modelError = null;
      return;
    }
    if (modelPhase != ModelInstallPhase.downloading) {
      modelPhase = ModelInstallPhase.idle;
    }
  }

  Future<void> downloadGemmaModel() async {
    if (modelPhase == ModelInstallPhase.downloading) {
      return;
    }
    modelPhase = ModelInstallPhase.downloading;
    modelProgress = 0;
    modelError = null;
    notifyListeners();

    try {
      await GemmaBootstrap.ensureInitialized();
      final bundledAsset = WorkerModelCatalog.bundledAssetFromEnvironment();
      var downloadUrl = WorkerModelCatalog.resolveDownloadUrl(_config.baseUrl);
      _logTask('Model download URL: $downloadUrl');
      if (bundledAsset == null && WorkerModelCatalog.usesBackendArtifactProxy()) {
        if (backendOnline) {
          downloadUrl = await _resolveDownloadUrlWithFallback(downloadUrl);
        } else {
          _logTask(
            'Backend offline — skipping proxy probe, using direct Hugging Face download',
          );
          downloadUrl = WorkerModelCatalog.huggingFaceDownloadUrl;
        }
      }
      try {
        await FlutterGemma.uninstallModel(WorkerModelCatalog.fileName);
        _logTask('Cleared any previous partial model install');
      } catch (_) {
        // No prior install — safe to ignore.
      }
      final installer = FlutterGemma.installModel(modelType: ModelType.qwen3);
      if (bundledAsset != null) {
        await installer.fromAsset(bundledAsset).install();
      } else {
        await installer
            .fromNetwork(downloadUrl)
            .withProgress((progress) {
              modelProgress = progress / 100.0;
              notifyListeners();
            })
            .install();
      }
      modelPhase = ModelInstallPhase.ready;
      modelProgress = 1;
      modelError = null;
    } catch (error, stackTrace) {
      WorkerTaskLog.error('Model download failed', error, stackTrace);
      modelPhase = ModelInstallPhase.failed;
      modelError = '$error';
      _logTask('Model download failed: $error');
    }
    lastSync = _formatNow();
    notifyListeners();
  }

  Future<String> _resolveDownloadUrlWithFallback(String proxyUrl) async {
    try {
      await _validateModelDownloadUrl(proxyUrl);
      return proxyUrl;
    } catch (error) {
      _logTask(
        'Backend proxy unavailable ($error) — using direct Hugging Face download',
      );
      return WorkerModelCatalog.huggingFaceDownloadUrl;
    }
  }

  Future<void> _validateModelDownloadUrl(String downloadUrl) async {
    final uri = Uri.parse(downloadUrl);
    _logTask('Probing download URL (Range bytes=0-0)…');
    final request = http.Request('GET', uri)
      ..headers['Range'] = 'bytes=0-0';
    final response = await _http.send(request).timeout(const Duration(seconds: 20));
    final status = response.statusCode;
    if (status != 200 && status != 206) {
      final body = await response.stream.bytesToString();
      throw StateError(
        'Model download unavailable (HTTP $status). '
        '${body.length > 240 ? "${body.substring(0, 240)}…" : body}',
      );
    }
    await response.stream.drain<void>();
    _logTask('Download URL probe OK (HTTP $status)');
  }

  bool get isGemmaReady => modelPhase == ModelInstallPhase.ready;

  bool get isGemmaDownloading => modelPhase == ModelInstallPhase.downloading;

  bool get canStartGemmaDownload => modelPhase != ModelInstallPhase.downloading;

  bool get requiresHuggingFaceToken => false;

  String get gemmaDownloadLabel => switch (modelPhase) {
        ModelInstallPhase.idle => 'Download ${WorkerModelCatalog.displayName}',
        ModelInstallPhase.downloading =>
          'Downloading ${WorkerModelCatalog.displayName}… ${(modelProgress * 100).toStringAsFixed(0)}%',
        ModelInstallPhase.ready => '${WorkerModelCatalog.displayName} installed',
        ModelInstallPhase.failed => 'Retry model download',
      };

  Future<void> pollAndRunTask() async {
    _logTask('Run task tapped — starting pollAndRunTask');
    _logTask('Worker base URL: ${_config.baseUrl}');
    _logTask(
      'Pre-checks: available=$available, modelPhase=$modelPhase, modelReady=$isGemmaReady',
    );

    try {
      await _refreshBackendHealth();
      _logTask(
        'Backend health: online=$backendOnline message="$backendMessage"',
      );
      if (!backendOnline) {
        _logTask('Aborting — backend offline');
        return;
      }
      if (modelPhase != ModelInstallPhase.ready) {
        modelError = 'Install the on-device model before running tasks.';
        _logTask('Aborting — model not ready (phase=$modelPhase)');
        return;
      }

      _logTask('Polling worker-gateway for next assignment…');
      final assignment = await _coordinator.pollAssignment();
      if (assignment == null) {
        _logTask('No assignment from backend — running local demo task');
        await _runLocalDemoTask();
        return;
      }

      _logTask(
        'Assignment received: id=${assignment.assignmentId} type=${assignment.taskType}',
      );
      await _coordinator.executeAssignment(assignment);
      _logTask(
        'Assignment finished: phase=${executionStatus.phase} detail=${executionStatus.detail ?? "(none)"}',
      );
      lastSync = _formatNow();
    } catch (error, stackTrace) {
      WorkerTaskLog.error('pollAndRunTask failed', error, stackTrace);
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

  Future<AssignmentInputBundle> _loadAssignmentInput(WorkerAssignment assignment) async {
    final inputBytes = Uint8List.fromList('Task ${assignment.taskType}: process assigned payload.'.codeUnits);
    return AssignmentInputBundle(
      inputBytes: inputBytes,
      inputDigest: sha256Hex(inputBytes),
      modelArtifact: ModelArtifact(
        modelVersionId: WorkerModelCatalog.modelVersionId,
        digestSha256: WorkerModelCatalog.installedDigestMarker,
        signatureSha256: WorkerModelCatalog.installedDigestMarker,
        backend: InferenceBackend.liteRt,
        bytes: Uint8List.fromList([0]),
      ),
    );
  }

  void _onExecutionStatus(ExecutionStatus status) {
    executionStatus = status;
    _logTask(
      'Execution status: phase=${status.phase} task=${status.taskType ?? "-"} progress=${status.progressMilli}',
    );
  }

  String _formatNow() => '${DateTime.now().hour.toString().padLeft(2, '0')}:'
      '${DateTime.now().minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _api.close();
    _http.close();
    super.dispose();
  }
}
