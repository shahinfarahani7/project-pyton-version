import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:http/http.dart' as http;

import 'api/worker_api_client.dart';
import 'api/worker_assignment_models.dart';
import 'config/worker_config.dart';
import 'models/gemma_model_catalog.dart';
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
  String? runtimeHuggingFaceToken;
  ExecutionStatus executionStatus = const ExecutionStatus(phase: ExecutionPhase.idle);
  String lastSync = 'never';

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

  Future<void> _refreshBackendHealth() async {
    try {
      final response = await _http
          .get(_config.resolve('/health/live'))
          .timeout(_config.requestTimeout);
      backendOnline = response.statusCode == 200;
      backendMessage = backendOnline
          ? 'Connected (${_config.baseUrl.host}:${_config.baseUrl.port})'
          : 'Backend returned ${response.statusCode}';
    } catch (error) {
      backendOnline = false;
      backendMessage = 'Unreachable: $error';
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

  Future<void> downloadGemmaModel({String? huggingFaceToken}) async {
    if (modelPhase == ModelInstallPhase.downloading) {
      return;
    }
    if (huggingFaceToken != null && huggingFaceToken.isNotEmpty) {
      runtimeHuggingFaceToken = huggingFaceToken;
    }
    modelPhase = ModelInstallPhase.downloading;
    modelProgress = 0;
    modelError = null;
    notifyListeners();

    try {
      await GemmaBootstrap.ensureInitialized();
      final token = _effectiveHuggingFaceToken;
      final bundledAsset = GemmaModelCatalog.bundledAssetFromEnvironment();
      final installer = FlutterGemma.installModel(modelType: ModelType.gemmaIt);
      if (bundledAsset != null) {
        await installer.fromAsset(bundledAsset).install();
      } else {
        await installer
            .fromNetwork(
              GemmaModelCatalog.downloadUrlFromEnvironment(),
              token: token.isEmpty ? null : token,
            )
            .withProgress((progress) {
              modelProgress = progress / 100.0;
              notifyListeners();
            })
            .install();
      }
      modelPhase = ModelInstallPhase.ready;
      modelProgress = 1;
      modelError = null;
    } catch (error) {
      modelPhase = ModelInstallPhase.failed;
      modelError = '$error';
    }
    lastSync = _formatNow();
    notifyListeners();
  }

  bool get isGemmaReady => modelPhase == ModelInstallPhase.ready;

  bool get isGemmaDownloading => modelPhase == ModelInstallPhase.downloading;

  bool get canStartGemmaDownload => modelPhase != ModelInstallPhase.downloading;

  bool get requiresHuggingFaceToken =>
      GemmaModelCatalog.bundledAssetFromEnvironment() == null && _effectiveHuggingFaceToken.isEmpty;

  String get gemmaDownloadLabel => switch (modelPhase) {
        ModelInstallPhase.idle => 'Download Gemma model',
        ModelInstallPhase.downloading =>
          'Downloading Gemma… ${(modelProgress * 100).toStringAsFixed(0)}%',
        ModelInstallPhase.ready => 'Gemma model installed',
        ModelInstallPhase.failed => 'Retry Gemma download',
      };

  String get _effectiveHuggingFaceToken {
    final runtime = runtimeHuggingFaceToken;
    if (runtime != null && runtime.isNotEmpty) {
      return runtime;
    }
    return GemmaModelCatalog.huggingFaceTokenFromEnvironment();
  }

  Future<void> pollAndRunTask() async {
    await _refreshBackendHealth();
    if (!backendOnline) {
      notifyListeners();
      return;
    }
    if (modelPhase != ModelInstallPhase.ready) {
      modelError = 'Install Gemma model before running tasks.';
      notifyListeners();
      return;
    }
    final assignment = await _coordinator.pollAssignment();
    if (assignment == null) {
      await _runLocalDemoTask();
      return;
    }
    await _coordinator.executeAssignment(assignment);
    lastSync = _formatNow();
    notifyListeners();
  }

  Future<void> _runLocalDemoTask() async {
    executionStatus = const ExecutionStatus(
      phase: ExecutionPhase.preparing,
      taskType: 'text.generate',
    );
    notifyListeners();

    final input = 'Summarize EdgeMint worker readiness in one sentence.';
    final adapter = GemmaLiteRtInferenceAdapter();
    await adapter.loadVerified(
      ModelArtifact(
        modelVersionId: GemmaModelCatalog.modelVersionId,
        digestSha256: GemmaModelCatalog.installedDigestMarker,
        signatureSha256: GemmaModelCatalog.installedDigestMarker,
        backend: InferenceBackend.liteRt,
        bytes: Uint8List.fromList([0]),
      ),
      signingKey: await _platform.signingMaterial(),
    );
    executionStatus = executionStatus.copyWith(phase: ExecutionPhase.running, progressMilli: 0);
    notifyListeners();
    final output = await adapter.run(
      inputBytes: Uint8List.fromList(utf8.encode(input)),
      resumedState: null,
      onProgress: (progress) async {
        executionStatus = executionStatus.copyWith(progressMilli: progress);
        notifyListeners();
      },
    );
    await adapter.dispose();
    executionStatus = ExecutionStatus(
      phase: ExecutionPhase.completed,
      progressMilli: 1000,
      detail: utf8.decode(output.resultBytes),
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
        modelVersionId: GemmaModelCatalog.modelVersionId,
        digestSha256: GemmaModelCatalog.installedDigestMarker,
        signatureSha256: GemmaModelCatalog.installedDigestMarker,
        backend: InferenceBackend.liteRt,
        bytes: Uint8List.fromList([0]),
      ),
    );
  }

  void _onExecutionStatus(ExecutionStatus status) {
    executionStatus = status;
    notifyListeners();
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
