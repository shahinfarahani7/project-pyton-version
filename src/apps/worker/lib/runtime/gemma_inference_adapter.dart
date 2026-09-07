import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart';

import '../models/worker_model_catalog.dart';
import 'gemma_model_runtime_manager.dart';
import 'inference_adapter.dart';
import 'model_runtime_manager.dart';
import 'runtime_exceptions.dart';

/// Runs task prompts through the active on-device Qwen2.5 model.
class GemmaLiteRtInferenceAdapter implements InferenceAdapter {
  GemmaLiteRtInferenceAdapter({
    GemmaModelRuntimeManager? runtimeManager,
  }) : _runtime = runtimeManager ?? GemmaModelRuntimeManager();

  final GemmaModelRuntimeManager _runtime;

  ModelRuntimeManager get runtimeManager => _runtime;

  static const _verboseTaskLogs = bool.fromEnvironment(
    'WORKER_VERBOSE_TASK_LOGS',
    defaultValue: false,
  );

  @override
  InferenceBackend get backend => InferenceBackend.liteRt;

  void _log(String message) {
    developer.log(message, name: 'EdgeMintModel');
  }

  String _preview(String value, {int maxLength = 500}) {
    final normalized = value.replaceAll('\n', ' ');
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength)}...';
  }

  @override
  Future<void> loadVerified(
    ModelArtifact artifact, {
    required String signingKey,
  }) {
    return _runtime.ensureResident(artifact: artifact, signingKey: signingKey);
  }

  @override
  Future<InferenceOutput> run({
    required Uint8List inputBytes,
    required Uint8List? resumedState,
    Future<void> Function(int progressMilli)? onProgress,
  }) {
    return _runtime.withFreshSession(
      stageId: 'inference',
      body: () => _runInFreshSession(
        inputBytes: inputBytes,
        resumedState: resumedState,
        onProgress: onProgress,
      ),
    );
  }

  Future<InferenceOutput> _runInFreshSession({
    required Uint8List inputBytes,
    required Uint8List? resumedState,
    Future<void> Function(int progressMilli)? onProgress,
  }) async {
    final model = _runtime.requireModel();
    final stopwatch = Stopwatch()..start();
    final prompt = utf8.decode(inputBytes);

    _log(
      '[LLM START] model=${WorkerModelCatalog.displayName} '
      'inputBytes=${inputBytes.length} promptChars=${prompt.length}',
    );
    if (_verboseTaskLogs) {
      _log('[LLM PROMPT] ${_preview(prompt)}');
    }

    try {
      await onProgress?.call(resumedState == null ? 100 : 500);

      _log('[LLM SESSION] creating');
      final chat = await model.createChat(
        systemInstruction:
            'You are EdgeMint worker AI. '
            'Answer concisely for the assigned task payload.',
      );
      _log('[LLM SESSION] created');

      try {
        await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
        await onProgress?.call(700);

        _log('[LLM INFERENCE] generation started');
        final reply = await chat.generateChatResponse();
        if (stopwatch.isRunning) {
          stopwatch.stop();
        }
        _log(
          '[LLM INFERENCE] generation completed elapsedMs=${stopwatch.elapsedMilliseconds}',
        );
        await onProgress?.call(1000);

        final text = switch (reply) {
          TextResponse(:final token) => token,
          ThinkingResponse(:final content) => content,
          FunctionCallResponse(:final name, :final args) => '$name(${args.toString()})',
          ParallelFunctionCallResponse(:final calls) =>
            calls.map((call) => '${call.name}(${call.args})').join(', '),
        };

        _log('[LLM OUTPUT] chars=${text.length} elapsedMs=${stopwatch.elapsedMilliseconds}');
        if (_verboseTaskLogs) {
          _log('[LLM RESPONSE] ${_preview(text)}');
        }

        return InferenceOutput(
          resultBytes: Uint8List.fromList(utf8.encode(text)),
          progressMilli: 1000,
          metrics: {
            'backend': backend.name,
            'modelProfile': WorkerModelCatalog.profileId,
            'inputBytes': inputBytes.length,
            'outputChars': text.length,
            'elapsedMs': stopwatch.elapsedMilliseconds,
            'maxTokens': 1280,
            'sessionStage': 'inference',
          },
        );
      } finally {
        try {
          await chat.session.close();
          _log('[LLM SESSION] closed');
        } catch (error, stackTrace) {
          developer.log(
            '[LLM SESSION] close failed: $error',
            name: 'EdgeMintModel',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    } catch (error, stackTrace) {
      if (stopwatch.isRunning) {
        stopwatch.stop();
      }
      developer.log(
        '[LLM ERROR] elapsedMs=${stopwatch.elapsedMilliseconds} error=$error',
        name: 'EdgeMintModel',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<void> dispose() {
    return _runtime.unload(reason: ModelUnloadReason.lifecycleShutdown, force: true);
  }
}
