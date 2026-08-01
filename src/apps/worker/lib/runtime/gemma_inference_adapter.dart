import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart';

import '../models/worker_model_catalog.dart';
import 'inference_adapter.dart';
import 'runtime_exceptions.dart';

/// Runs task prompts through the on-device Qwen3 LiteRT-LM model.
class GemmaLiteRtInferenceAdapter implements InferenceAdapter {
  InferenceModel? _model;
  bool _loaded = false;

  @override
  InferenceBackend get backend => InferenceBackend.liteRt;

  @override
  Future<void> loadVerified(ModelArtifact artifact, {required String signingKey}) async {
    if (artifact.backend != InferenceBackend.liteRt) {
      throw ModelIntegrityException('Expected LiteRT model artifact');
    }
    if (artifact.digestSha256 != WorkerModelCatalog.installedDigestMarker &&
        artifact.modelVersionId != WorkerModelCatalog.modelVersionId) {
      throw ModelIntegrityException('Unexpected model version for worker runtime');
    }
    final active = await FlutterGemma.getActiveModel(
      maxTokens: 4096,
      preferredBackend: PreferredBackend.cpu,
    );
    _model = active;
    _loaded = true;
  }

  @override
  Future<InferenceOutput> run({
    required Uint8List inputBytes,
    required Uint8List? resumedState,
    Future<void> Function(int progressMilli)? onProgress,
  }) async {
    if (!_loaded || _model == null) {
      throw StateError('On-device model not loaded');
    }
    await onProgress?.call(resumedState == null ? 100 : 500);
    final prompt = utf8.decode(inputBytes);
    final chat = await _model!.createChat(
      maxOutputTokens: 256,
      systemInstruction:
          'You are EdgeMint worker AI. Answer concisely for the assigned task payload.',
    );
    await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
    await onProgress?.call(700);
    final reply = await chat.generateChatResponse();
    await onProgress?.call(1000);
    final text = switch (reply) {
      TextResponse(:final token) => token,
      ThinkingResponse(:final content) => content,
      FunctionCallResponse(:final name, :final args) => '$name(${args.toString()})',
      ParallelFunctionCallResponse(:final calls) =>
        calls.map((call) => '${call.name}(${call.args})').join(', '),
    };
    return InferenceOutput(
      resultBytes: Uint8List.fromList(text.codeUnits),
      progressMilli: 1000,
      metrics: {
        'backend': backend.name,
        'modelProfile': WorkerModelCatalog.profileId,
        'inputBytes': inputBytes.length,
        'outputChars': text.length,
      },
    );
  }

  @override
  Future<void> dispose() async {
    await _model?.close();
    _model = null;
    _loaded = false;
  }
}
