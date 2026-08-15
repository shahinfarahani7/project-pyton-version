import 'dart:convert';
import 'dart:typed_data';

import '../../contracts/worker_error.dart';
import '../../models/worker_model_catalog.dart';
import '../../runtime/gemma_inference_adapter.dart';
import '../../runtime/inference_adapter.dart';
import '../../validation/json_output_validator.dart';
import 'prompt_templates.dart';

class QwenInferenceConfig {
  const QwenInferenceConfig({
    this.contextSize = 2048,
    this.maxOutputTokens = 256,
    this.temperature = 0.1,
    this.topP = 0.8,
    this.topK = 20,
    this.repeatPenalty = 1.05,
  });

  final int contextSize;
  final int maxOutputTokens;
  final double temperature;
  final double topP;
  final int topK;
  final double repeatPenalty;
}

typedef LlmRunner = Future<String> Function(String prompt);

class QwenTaskProcessor {
  QwenTaskProcessor({
    GemmaLiteRtInferenceAdapter? adapter,
    LlmRunner? runner,
    this.config = const QwenInferenceConfig(),
  })  : _adapter = adapter ?? GemmaLiteRtInferenceAdapter(),
        _runner = runner;

  final GemmaLiteRtInferenceAdapter _adapter;
  final LlmRunner? _runner;
  final QwenInferenceConfig config;
  bool _loaded = false;

  Future<void> ensureLoaded({required String signingKey}) async {
    if (_loaded) {
      return;
    }
    await _adapter.loadVerified(
      ModelArtifact(
        modelVersionId: WorkerModelCatalog.modelVersionId,
        digestSha256: WorkerModelCatalog.installedDigestMarker,
        signatureSha256: WorkerModelCatalog.installedDigestMarker,
        backend: InferenceBackend.liteRt,
        bytes: Uint8List.fromList([0]),
      ),
      signingKey: signingKey,
    );
    _loaded = true;
  }

  Future<Map<String, dynamic>> runJsonTask({
    required String prompt,
    Map<String, dynamic>? outputSchema,
    required String signingKey,
  }) async {
    final raw = await _runPrompt(prompt, signingKey: signingKey);
    var parsed = JsonOutputValidator.parseJsonObject(raw);
    if (parsed == null) {
      final repairPrompt = PromptTemplates.jsonRepair(brokenJson: raw);
      final repaired = await _runPrompt(repairPrompt, signingKey: signingKey);
      parsed = JsonOutputValidator.parseJsonObject(repaired);
    }
    if (parsed == null) {
      throw const WorkerError(
        code: WorkerErrorCode.llmInvalidJson,
        message: 'LLM output is not valid JSON after repair attempt',
        retryable: true,
        stage: WorkerTaskStage.llm,
      );
    }
    final schemaError = JsonOutputValidator.validateSchema(parsed, outputSchema);
    if (schemaError != null) {
      throw schemaError;
    }
    return parsed;
  }

  Future<String> _runPrompt(String prompt, {required String signingKey}) async {
    if (_runner != null) {
      return _runner!(prompt);
    }
    await ensureLoaded(signingKey: signingKey);
    final output = await _adapter.run(
      inputBytes: Uint8List.fromList(utf8.encode(prompt)),
      resumedState: null,
    );
    return utf8.decode(output.resultBytes);
  }

  Future<void> dispose() async {
    if (_runner == null) {
      await _adapter.dispose();
    }
    _loaded = false;
  }
}
