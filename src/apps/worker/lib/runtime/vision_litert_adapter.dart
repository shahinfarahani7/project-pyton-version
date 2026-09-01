import 'package:convert/convert.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_gemma/core/di/service_registry.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:crypto/crypto.dart';

import '../contracts/worker_error.dart';
import '../models/worker_vision_model_catalog.dart';
import '../validation/json_output_validator.dart';

/// Strict on-device InternVL adapter. It never falls back to metadata or OCR.
class VisionLiteRtAdapter {
  InferenceModel? _model;
  bool _verified = false;

  Future<void> ensureLoaded() async {
    final id = WorkerVisionModelCatalog.fileName;
    if (!await FlutterGemma.isModelInstalled(id)) {
      await WorkerVisionModelCatalog.installBuilder()
          .fromNetwork(WorkerVisionModelCatalog.downloadUrl, foreground: true)
          .install();
    }
    final path = await ServiceRegistry.instance.fileSystemService.getReadTargetPath(
      id,
    );
    if (!await File(path).exists()) {
      throw const WorkerError(
        code: WorkerErrorCode.modelNotAvailable,
        message: 'InternVL3 model registry entry has no artifact',
        retryable: true,
        stage: WorkerTaskStage.llm,
      );
    }
    if (!_verified) {
      final digestSink = AccumulatorSink<Digest>();
      final converter = sha256.startChunkedConversion(digestSink);
      await for (final chunk in File(path).openRead()) {
        converter.add(chunk);
      }
      converter.close();
      if (digestSink.events.single.toString() !=
          WorkerVisionModelCatalog.artifactSha256) {
        await FlutterGemma.uninstallModel(id);
        throw const WorkerError(
          code: WorkerErrorCode.modelNotAvailable,
          message: 'InternVL3 artifact SHA-256 mismatch',
          retryable: false,
          stage: WorkerTaskStage.llm,
        );
      }
      _verified = true;
    }
    await _model?.close();
    await WorkerVisionModelCatalog.installBuilder().fromFile(path).install();
    _model = await FlutterGemma.getActiveModel(
      maxTokens: 4096,
      preferredBackend: PreferredBackend.cpu,
    );
  }

  Future<Map<String, dynamic>> runJson({
    required Uint8List imageBytes,
    required String prompt,
    required Map<String, dynamic> outputSchema,
  }) async {
    final raw = await runRaw(imageBytes: imageBytes, prompt: prompt);
    final parsed = JsonOutputValidator.parseJsonObject(raw);
    if (parsed == null)
      throw WorkerError(
        code: WorkerErrorCode.llmInvalidJson,
        message: raw,
        retryable: true,
        stage: WorkerTaskStage.llm,
      );
    final error = JsonOutputValidator.validateSchema(parsed, outputSchema);
    if (error != null) throw error;
    return parsed;
  }

  Future<String> runRaw({
    required Uint8List imageBytes,
    required String prompt,
  }) async {
    await ensureLoaded();
    final chat = await _model!.createChat(
      maxOutputTokens: 512,
      supportImage: true,
      modelType: ModelType.general,
      isThinking: false,
      temperature: 0.0,
      randomSeed: 42,
      systemInstruction:
          'You are EdgeMint visual worker. Output strict JSON only.',
    );
    await chat.addQueryChunk(
      Message.withImage(text: prompt, imageBytes: imageBytes, isUser: true),
    );
    final reply = await chat.generateChatResponse();
    final raw = switch (reply) {
      TextResponse(:final token) => token,
      ThinkingResponse(:final content) => content,
      _ => '',
    };
    await chat.close();
    return raw;
  }

  Future<void> dispose() async {
    await _model?.close();
    _model = null;
    _verified = false;
  }
}
