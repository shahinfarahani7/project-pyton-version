import 'dart:typed_data';

import 'package:edgemint_worker/contracts/worker_error.dart';
import 'package:edgemint_worker/models/worker_model_catalog.dart';
import 'package:edgemint_worker/runtime/gemma_model_runtime_manager.dart';
import 'package:edgemint_worker/runtime/inference_adapter.dart';
import 'package:edgemint_worker/tasks/task_execution_plan_policy.dart';
import 'package:edgemint_worker/tasks/task_type_mapper.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/tool.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TaskExecutionPlanPolicy', () {
    test('text.direct bypasses execution plan session shell', () {
      expect(
        TaskExecutionPlanPolicy.usesExecutionPlanShell(
          v1Type: TaskTypeMapper.textDirect,
          requiresLlm: true,
          requiresNativeRuntime: true,
          usesMapReduceShell: false,
          executionPlanRunnerInjected: false,
        ),
        isFalse,
      );
    });

    test('summarize map-reduce still uses execution plan shell', () {
      expect(
        TaskExecutionPlanPolicy.usesExecutionPlanShell(
          v1Type: TaskTypeMapper.textSummarize,
          requiresLlm: true,
          requiresNativeRuntime: true,
          usesMapReduceShell: true,
          executionPlanRunnerInjected: false,
        ),
        isTrue,
      );
    });

    test('summarize without native runtime or injected runner bypasses plan shell', () {
      expect(
        TaskExecutionPlanPolicy.usesExecutionPlanShell(
          v1Type: TaskTypeMapper.textSummarize,
          requiresLlm: true,
          requiresNativeRuntime: false,
          usesMapReduceShell: true,
          executionPlanRunnerInjected: false,
        ),
        isFalse,
      );
    });
  });

  group('Gemma multimodal session order', () {
    late _RecordingLoader loader;
    late GemmaModelRuntimeManager manager;
    final artifact = ModelArtifact(
      modelVersionId: WorkerModelCatalog.modelVersionId,
      digestSha256: WorkerModelCatalog.installedDigestMarker,
      signatureSha256: WorkerModelCatalog.installedAttestationSignature('sign'),
      backend: InferenceBackend.liteRt,
      bytes: Uint8List.fromList([0]),
    );

    setUp(() {
      loader = _RecordingLoader();
      manager = GemmaModelRuntimeManager(activeModelLoader: loader.load);
    });

    test('first image task upgrades at activeSessions=0 then opens session', () async {
      await manager.ensureResident(artifact: artifact, signingKey: 'sign');
      expect(manager.openSessionCount, 0);

      await manager.ensureMultimodalVisionEngine();
      expect(manager.openSessionCount, 0);
      expect(manager.visionExecutorLoaded, isTrue);
      expect(loader.calls.length, 2);

      await manager.withFreshSession(
        stageId: 'multimodal',
        sessionOwner: 'GemmaLiteRtInferenceAdapter.runUserPrompt',
        body: () async {},
      );
      expect(loader.calls.length, 2);
    });

    test('second image task does not reload engine', () async {
      await manager.ensureResident(artifact: artifact, signingKey: 'sign');
      await manager.ensureMultimodalVisionEngine();
      final afterFirstUpgrade = loader.calls.length;

      await manager.ensureMultimodalVisionEngine();
      expect(loader.calls.length, afterFirstUpgrade);
    });

    test('text task after vision reuses resident engine without reload', () async {
      await manager.ensureResident(artifact: artifact, signingKey: 'sign');
      await manager.ensureMultimodalVisionEngine();
      final afterVision = loader.calls.length;

      await manager.ensureResident(artifact: artifact, signingKey: 'sign');
      expect(loader.calls.length, afterVision);
      expect(manager.visionExecutorLoaded, isTrue);
    });

    test('plan-runner session blocks vision upgrade (regression guard)', () async {
      await manager.ensureResident(artifact: artifact, signingKey: 'sign');
      await manager.withFreshSession(
        stageId: 'llm-direct',
        sessionOwner: 'ExecutionPlanRunner.runStage:llm_infer',
        body: () async {
          expect(manager.openSessionCount, 1);
          await expectLater(
            manager.ensureMultimodalVisionEngine(),
            throwsA(isA<WorkerError>()),
          );
        },
      );
    });
  });
}

class _RecordingLoader {
  final calls = <_LoadCall>[];

  Future<InferenceModel> load({
    required int maxTokens,
    required PreferredBackend preferredBackend,
    required bool supportImage,
    required int maxNumImages,
  }) async {
    calls.add(
      _LoadCall(
        maxTokens: maxTokens,
        preferredBackend: preferredBackend,
        supportImage: supportImage,
        maxNumImages: maxNumImages,
      ),
    );
    return _StubInferenceModel(maxTokens: maxTokens);
  }
}

class _LoadCall {
  _LoadCall({
    required this.maxTokens,
    required this.preferredBackend,
    required this.supportImage,
    required this.maxNumImages,
  });

  final int maxTokens;
  final PreferredBackend preferredBackend;
  final bool supportImage;
  final int maxNumImages;
}

class _StubInferenceModel implements InferenceModel {
  _StubInferenceModel({required this.maxTokens});

  @override
  final int maxTokens;

  @override
  InferenceModelSession? session;

  @override
  InferenceChat? chat;

  @override
  ModelFileType get fileType => ModelFileType.litertlm;

  @override
  PreferredBackend? get activeBackend => PreferredBackend.gpu;

  @override
  Future<void> close() async {}

  @override
  void addCloseListener(void Function() listener) {}

  @override
  Future<InferenceChat> openChat({
    double temperature = .8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    int tokenBuffer = 256,
    String? loraPath,
    bool? supportImage,
    bool? supportAudio,
    List<Tool> tools = const [],
    bool? supportsFunctionCalls,
    bool isThinking = false,
    ModelType? modelType,
    ToolChoice toolChoice = ToolChoice.auto,
    int? maxFunctionBufferLength,
    String? systemInstruction,
    int? maxOutputTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<InferenceModelSession> createSession({
    double temperature = .8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    String? loraPath,
    bool? enableVisionModality,
    bool? enableAudioModality,
    String? systemInstruction,
    bool enableThinking = false,
    List<Tool> tools = const [],
    int? maxOutputTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<InferenceChat> createChat({
    double temperature = .8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    int tokenBuffer = 256,
    String? loraPath,
    bool? supportImage,
    bool? supportAudio,
    List<Tool> tools = const [],
    bool? supportsFunctionCalls,
    bool isThinking = false,
    ModelType? modelType,
    ToolChoice toolChoice = ToolChoice.auto,
    int? maxFunctionBufferLength,
    String? systemInstruction,
    int? maxOutputTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<InferenceModelSession> openSession({
    double temperature = .8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    String? loraPath,
    bool? enableVisionModality,
    bool? enableAudioModality,
    String? systemInstruction,
    bool enableThinking = false,
    List<Tool> tools = const [],
    int? maxOutputTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  List<InferenceModelSession> get sessions => const [];
}
