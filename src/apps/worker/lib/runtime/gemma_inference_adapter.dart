import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart';

import '../models/worker_model_catalog.dart';
import 'inference_adapter.dart';
import 'runtime_exceptions.dart';

/// Runs task prompts through the active on-device Qwen2.5 model.
class GemmaLiteRtInferenceAdapter implements InferenceAdapter {
  InferenceModel? _model;
  bool _loaded = false;

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

  // ---------------------------------------------------------------------------
  // Load model
  // ---------------------------------------------------------------------------

  @override
  Future<void> loadVerified(
    ModelArtifact artifact, {
    required String signingKey,
  }) async {
    // Model is already loaded by this adapter.
    // Do not create another native model instance.
    if (_loaded && _model != null) {
      _log(
        '[MODEL LOAD] already loaded '
        'model=${WorkerModelCatalog.displayName}',
      );

      return;
    }

    if (artifact.backend != InferenceBackend.liteRt) {
      throw ModelIntegrityException('Expected LiteRT model artifact');
    }

    if (artifact.digestSha256 != WorkerModelCatalog.installedDigestMarker &&
        artifact.modelVersionId != WorkerModelCatalog.modelVersionId) {
      throw ModelIntegrityException(
        'Unexpected model version for worker runtime',
      );
    }

    _log(
      '[MODEL LOAD] '
      'profile=${WorkerModelCatalog.profileId} '
      'model=${WorkerModelCatalog.displayName}',
    );

    try {
      //
      // IMPORTANT:
      //
      // The installed Qwen artifact is:
      //
      // Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task
      //
      // Therefore the MediaPipe model context must not be configured
      // with the old 4096-token value.
      //
      final active = await FlutterGemma.getActiveModel(
        maxTokens: 1280,
        preferredBackend: PreferredBackend.cpu,
      );

      _model = active;
      _loaded = true;

      _log(
        '[MODEL LOAD] successful '
        'model=${WorkerModelCatalog.displayName} '
        'maxTokens=1280',
      );
    } catch (error, stackTrace) {
      _model = null;
      _loaded = false;

      developer.log(
        '[MODEL LOAD] failed: $error',
        name: 'EdgeMintModel',
        error: error,
        stackTrace: stackTrace,
      );

      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Run inference
  // ---------------------------------------------------------------------------

  @override
  Future<InferenceOutput> run({
    required Uint8List inputBytes,
    required Uint8List? resumedState,
    Future<void> Function(int progressMilli)? onProgress,
  }) async {
    final model = _model;

    if (!_loaded || model == null) {
      throw StateError('On-device model not loaded');
    }

    final stopwatch = Stopwatch()..start();

    final prompt = utf8.decode(inputBytes);

    _log(
      '[LLM START] '
      'model=${WorkerModelCatalog.displayName} '
      'inputBytes=${inputBytes.length} '
      'promptChars=${prompt.length}',
    );

    if (_verboseTaskLogs) {
      _log('[LLM PROMPT] ${_preview(prompt)}');
    }

    try {
      await onProgress?.call(resumedState == null ? 100 : 500);

      // -----------------------------------------------------------------------
      // Create one fresh chat/session for this task.
      // -----------------------------------------------------------------------

      _log('[LLM SESSION] creating');

      final chat = await model.createChat(
        // Do NOT set maxOutputTokens here for the current .task path.
        systemInstruction:
            'You are EdgeMint worker AI. '
            'Answer concisely for the assigned task payload.',
      );

      _log('[LLM SESSION] created');

      try {
        // ---------------------------------------------------------------------
        // Prompt
        // ---------------------------------------------------------------------

        await chat.addQueryChunk(Message.text(text: prompt, isUser: true));

        await onProgress?.call(700);

        // ---------------------------------------------------------------------
        // Native inference
        // ---------------------------------------------------------------------

        _log('[LLM INFERENCE] generation started');

        final reply = await chat.generateChatResponse();

        if (stopwatch.isRunning) {
          stopwatch.stop();
        }

        _log(
          '[LLM INFERENCE] '
          'generation completed '
          'elapsedMs=${stopwatch.elapsedMilliseconds}',
        );

        await onProgress?.call(1000);

        // ---------------------------------------------------------------------
        // Response conversion
        // ---------------------------------------------------------------------

        final text = switch (reply) {
          TextResponse(:final token) => token,

          ThinkingResponse(:final content) => content,

          FunctionCallResponse(:final name, :final args) =>
            '$name(${args.toString()})',

          ParallelFunctionCallResponse(:final calls) =>
            calls.map((call) => '${call.name}(${call.args})').join(', '),
        };

        _log(
          '[LLM OUTPUT] '
          'chars=${text.length} '
          'elapsedMs=${stopwatch.elapsedMilliseconds}',
        );

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
          },
        );
      } finally {
        // ---------------------------------------------------------------------
        // IMPORTANT:
        //
        // Every EdgeMint task must get a fresh session.
        //
        // Close only the chat/session here.
        // DO NOT close the model.
        //
        // The model stays loaded for the next task.
        // ---------------------------------------------------------------------

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
        '[LLM ERROR] '
        'elapsedMs=${stopwatch.elapsedMilliseconds} '
        'error=$error',
        name: 'EdgeMintModel',
        error: error,
        stackTrace: stackTrace,
      );

      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Dispose model
  // ---------------------------------------------------------------------------

  @override
  Future<void> dispose() async {
    final model = _model;

    // Immediately mark this adapter unusable so nothing can start
    // another inference while shutdown is in progress.
    _model = null;
    _loaded = false;

    if (model == null) {
      _log('[MODEL CLOSE] no loaded model');

      return;
    }

    try {
      await model.close();

      _log('[MODEL CLOSE] completed');
    } catch (error, stackTrace) {
      developer.log(
        '[MODEL CLOSE] failed: $error',
        name: 'EdgeMintModel',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
