import 'dart:convert';
import 'dart:typed_data';

import '../../contracts/worker_error.dart';
import '../../models/worker_model_catalog.dart';
import '../../runtime/gemma_inference_adapter.dart';
import '../../runtime/inference_adapter.dart';
import '../../runtime/checkpoint_manager.dart';
import '../../runtime/model_runtime_manager.dart';
import '../../validation/json_output_validator.dart';
import 'context_budget_manager.dart';
import 'formatted_prompt_builder.dart';
import 'hierarchical_summarize_pipeline.dart';
import 'output_limit_enforcer.dart';
import 'prompt_templates.dart';
import 'semantic_chunk_engine.dart';

class QwenInferenceConfig {
  const QwenInferenceConfig({
    this.contextSize = ContextBudgetProfile.qwenBaselineTotalContextTokens,
    this.maxOutputTokens = ContextBudgetProfile.qwenBaselineOutputReserveTokens,
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
    ContextBudgetManager? contextBudget,
    SemanticChunkEngine? chunkEngine,
    CheckpointManager? checkpointManager,
    OutputLimitEnforcer? outputLimitEnforcer,
    this.config = const QwenInferenceConfig(),
  })  : _adapter = adapter ?? GemmaLiteRtInferenceAdapter(),
        _runner = runner,
        _contextBudget = contextBudget ?? const ContextBudgetManager(),
        _chunkEngine = chunkEngine ?? const SemanticChunkEngine(),
        _checkpointManager = checkpointManager,
        _outputLimitEnforcer = outputLimitEnforcer ?? const OutputLimitEnforcer();

  final GemmaLiteRtInferenceAdapter _adapter;
  final LlmRunner? _runner;
  final ContextBudgetManager _contextBudget;
  final SemanticChunkEngine _chunkEngine;
  final CheckpointManager? _checkpointManager;
  final OutputLimitEnforcer _outputLimitEnforcer;
  final QwenInferenceConfig config;

  ModelRuntimeManager get modelRuntimeManager => _adapter.runtimeManager;

  ContextBudgetManager get contextBudget => _contextBudget;

  SemanticChunkEngine get chunkEngine => _chunkEngine;

  ChunkPlan planInputChunks(String inputText) => _chunkEngine.chunk(inputText);

  bool _loaded = false;

  Future<void> ensureLoaded({required String signingKey}) async {
    // Another task may have activated InternVL; always re-select the exact
    // verified Qwen artifact before text generation.
    await _adapter.loadVerified(
      ModelArtifact(
        modelVersionId: WorkerModelCatalog.modelVersionId,
        digestSha256: WorkerModelCatalog.installedDigestMarker,
        signatureSha256: WorkerModelCatalog.installedAttestationSignature(signingKey),
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
    return _parseJsonResponse(
      raw: raw,
      outputSchema: outputSchema,
      signingKey: signingKey,
    );
  }

  Future<Map<String, dynamic>> runSummarizeJsonTask({
    required String inputText,
    required String signingKey,
    Map<String, dynamic>? outputSchema,
    String? assignmentId,
    int? fenceToken,
    Future<void> Function(ChunkCheckpointRecord record)? onChunkCheckpoint,
  }) async {
    final plan = planInputChunks(inputText);
    final checkpointScope = assignmentId != null &&
            fenceToken != null &&
            _checkpointManager != null
        ? SummarizeCheckpointScope(
            assignmentId: assignmentId,
            fenceToken: fenceToken,
            checkpointManager: _checkpointManager!,
            onChunkSaved: onChunkCheckpoint,
          )
        : null;
    final pipeline = HierarchicalSummarizePipeline(
      contextBudget: _contextBudget,
      runPromptJson: (prompt) => runJsonTask(
        prompt: prompt,
        outputSchema: outputSchema,
        signingKey: signingKey,
      ),
    );
    return pipeline.summarize(
      inputText: inputText,
      plan: plan,
      checkpointScope: checkpointScope,
    );
  }

  Future<Map<String, dynamic>> _parseJsonResponse({
    required String raw,
    Map<String, dynamic>? outputSchema,
    required String signingKey,
  }) async {
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
    final formatted = FormattedPromptBuilder.buildTaskPrompt(
      templateBody: prompt,
      systemInstruction: _contextBudget.defaultSystemInstruction,
    );
    _contextBudget.ensureDirectInferenceOrThrow(
      prompt: prompt,
      maxOutputTokens: config.maxOutputTokens,
    );
    if (_runner != null) {
      final raw = await _runner!(formatted);
      return _enforceOutputLimit(raw);
    }
    await ensureLoaded(signingKey: signingKey);
    final output = await _adapter.run(
      inputBytes: Uint8List.fromList(utf8.encode(formatted)),
      resumedState: null,
    );
    return _enforceOutputLimit(utf8.decode(output.resultBytes));
  }

  String _enforceOutputLimit(String raw) {
    final evaluation = _outputLimitEnforcer.evaluate(
      rawOutput: raw,
      maxOutputTokens: _contextBudget.capMaxOutputTokens(config.maxOutputTokens),
      jsonRequired: false,
    );
    if (!evaluation.treatAsSuccess) {
      throw OutputLimitExceededException(evaluation);
    }
    return raw;
  }

  Future<void> dispose() async {
    if (_runner == null) {
      await _adapter.dispose();
    }
    _loaded = false;
  }
}
