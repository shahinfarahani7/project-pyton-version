import 'dart:typed_data';

import 'package:edgemint_worker/contracts/worker_error.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/runtime/gemma4_e4b_gpu_benchmark.dart';
import 'package:edgemint_worker/runtime/gemma_inference_adapter.dart';
import 'package:edgemint_worker/runtime/gemma_model_runtime_manager.dart';
import 'package:edgemint_worker/runtime/inference_adapter.dart';
import 'package:edgemint_worker/models/worker_model_catalog.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/tool.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GemmaModelRuntimeManager multimodal vision', () {
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
      manager = GemmaModelRuntimeManager(
        activeModelLoader: loader.load,
      );
    });

    test('text-only resident load uses supportImage false', () async {
      await manager.ensureResident(artifact: artifact, signingKey: 'sign');
      expect(loader.calls.length, 1);
      expect(loader.calls.single.supportImage, isFalse);
      expect(loader.calls.single.maxNumImages, 0);
      expect(manager.visionExecutorLoaded, isFalse);
      expect(manager.configuredMaxNumImages, 0);
    });

    test('image task after text-only resident upgrades once', () async {
      await manager.ensureResidentForAssignment(
        artifact: artifact,
        signingKey: 'sign',
        enableVision: false,
      );
      expect(manager.lastCapabilityAction, 'load');
      expect(manager.lastRequestedCapability, 'text');
      expect(manager.lastResidentCapability, 'none');

      await manager.ensureResidentForAssignment(
        artifact: artifact,
        signingKey: 'sign',
        enableVision: true,
      );
      expect(loader.calls.length, 2);
      expect(loader.calls.first.supportImage, isFalse);
      expect(loader.calls.last.supportImage, isTrue);
      expect(loader.calls.last.maxNumImages, 1);
      expect(loader.calls.last.maxTokens, Gemma4E4bBenchmarkMode.residentMaxTokens);
      expect(manager.lastCapabilityAction, 'upgrade');
      expect(manager.lastRequestedCapability, 'vision');
      expect(manager.lastResidentCapability, 'text');
      expect(manager.visionExecutorLoaded, isTrue);
      expect(manager.openSessionCount, 0);
    });

    test('first image task with no resident engine loads multimodal directly', () async {
      await manager.ensureResidentForAssignment(
        artifact: artifact,
        signingKey: 'sign',
        enableVision: true,
      );
      expect(loader.calls.length, 1);
      expect(loader.calls.single.supportImage, isTrue);
      expect(loader.calls.single.maxNumImages, 1);
      expect(loader.calls.single.maxTokens, Gemma4E4bBenchmarkMode.residentMaxTokens);
      expect(manager.lastRequestedCapability, 'vision');
      expect(manager.lastResidentCapability, 'none');
      expect(manager.lastCapabilityAction, 'load');
      expect(manager.visionExecutorLoaded, isTrue);
      expect(manager.openSessionCount, 0);

      await manager.ensureMultimodalVisionEngine();
      expect(loader.calls.length, 1);
      expect(manager.lastCapabilityAction, 'reuse');
    });

    test('image task after multimodal resident engine does not reload', () async {
      await manager.ensureResidentForAssignment(
        artifact: artifact,
        signingKey: 'sign',
        enableVision: true,
      );
      await manager.ensureResidentForAssignment(
        artifact: artifact,
        signingKey: 'sign',
        enableVision: true,
      );
      expect(loader.calls.length, 1);
      expect(manager.lastRequestedCapability, 'vision');
      expect(manager.lastResidentCapability, 'vision');
      expect(manager.lastCapabilityAction, 'reuse');
    });

    test('text task after multimodal resident engine reuses without downgrade', () async {
      await manager.ensureResidentForAssignment(
        artifact: artifact,
        signingKey: 'sign',
        enableVision: true,
      );
      await manager.ensureResidentForAssignment(
        artifact: artifact,
        signingKey: 'sign',
        enableVision: false,
      );
      expect(loader.calls.length, 1);
      expect(loader.calls.single.supportImage, isTrue);
      expect(manager.visionExecutorLoaded, isTrue);
      expect(manager.lastRequestedCapability, 'text');
      expect(manager.lastResidentCapability, 'vision');
      expect(manager.lastCapabilityAction, 'reuse');
    });

    test('processor image preload loads vision once before session open', () async {
      final processor = QwenTaskProcessor(
        adapter: GemmaLiteRtInferenceAdapter(runtimeManager: manager),
      );
      await processor.ensureRuntimeResident(
        signingKey: 'sign',
        requireVision: true,
      );
      expect(loader.calls.length, 1);
      expect(loader.calls.single.supportImage, isTrue);
      expect(loader.calls.single.maxNumImages, 1);
      expect(loader.calls.single.maxTokens, Gemma4E4bBenchmarkMode.residentMaxTokens);
      expect(manager.openSessionCount, 0);

      await manager.ensureMultimodalVisionEngine();
      expect(loader.calls.length, 1);
      expect(manager.lastCapabilityAction, 'reuse');
    });

    test('vision upgrade while session open is VISION_RUNTIME_NOT_READY', () async {
      await manager.ensureResident(artifact: artifact, signingKey: 'sign');
      await manager.withFreshSession(stageId: 'test', body: () async {
        expect(
          () => manager.ensureMultimodalVisionEngine(),
          throwsA(
            isA<WorkerError>().having(
              (e) => e.code,
              'code',
              WorkerErrorCode.visionRuntimeNotReady,
            ),
          ),
        );
      });
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
