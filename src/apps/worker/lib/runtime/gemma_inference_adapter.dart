import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart';

import '../contracts/worker_error.dart';
import '../inference/llm/context_budget_manager.dart';
import '../models/worker_model_catalog.dart';
import '../validation/json_stream_boundary.dart';
import '../validation/output_repetition_guard.dart';
import 'gemma_multimodal_vision_runtime.dart';
import 'gemma_model_runtime_manager.dart';
import 'inference_adapter.dart';
import 'model_runtime_manager.dart';
import 'worker_pipeline_log.dart';

class _BoundedGeneration {
  const _BoundedGeneration({required this.text, required this.stopReason});

  final String text;
  final String stopReason;
}

/// Runs task prompts through the active on-device Gemma model.
class GemmaLiteRtInferenceAdapter implements InferenceAdapter {
  GemmaLiteRtInferenceAdapter({
    GemmaModelRuntimeManager? runtimeManager,
    this.maxOutputTokens = 256,
    this.temperature = 0.1,
    this.topK = 20,
    this.topP = 0.8,
  }) : _runtime = runtimeManager ?? GemmaModelRuntimeManager();

  final GemmaModelRuntimeManager _runtime;
  final int maxOutputTokens;
  final double temperature;
  final int topK;
  final double topP;

  /// When true, omit the default EdgeMint system instruction (portal direct prompt).
  bool usePortalPassthroughChat = false;

  ModelRuntimeManager get runtimeManager => _runtime;

  @override
  InferenceBackend get backend => InferenceBackend.liteRt;

  void _log(String message) {
    WorkerPipelineLog.info(WorkerPipelineLog.exec, message);
  }

  String _preview(String value, {int maxLength = 1200}) {
    final normalized = value.replaceAll('\n', r'\n');
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
    return runUserPrompt(
      prompt: utf8.decode(inputBytes),
      imageBytes: null,
      resumedState: resumedState,
      onProgress: onProgress,
    );
  }

  /// Text-only or multimodal user turn through the resident Gemma model.
  Future<InferenceOutput> runUserPrompt({
    required String prompt,
    Uint8List? imageBytes,
    required Uint8List? resumedState,
    Future<void> Function(int progressMilli)? onProgress,
    int? maxOutputTokensOverride,
  }) async {
    final multimodal = imageBytes != null && imageBytes.isNotEmpty;
    if (multimodal) {
      try {
        await _runtime.ensureMultimodalVisionEngine();
      } on WorkerError {
        rethrow;
      } catch (error) {
        final classified = GemmaLitertMultimodalVisionPolicy.classifyInferenceFailure(
          error,
        );
        if (classified != null) {
          throw classified;
        }
        rethrow;
      }
    } else {
      _log(
        GemmaLitertMultimodalVisionPolicy.visionRuntimeLogLine(
          visionExecutorLoaded: _runtime.visionExecutorLoaded,
          multimodal: false,
        ),
      );
    }

    return _runtime.withFreshSession(
      stageId: multimodal ? 'multimodal' : 'inference',
      sessionOwner: 'GemmaLiteRtInferenceAdapter.runUserPrompt',
      body: () => _runInFreshSession(
        prompt: prompt,
        imageBytes: imageBytes,
        resumedState: resumedState,
        onProgress: onProgress,
        maxOutputTokensOverride: maxOutputTokensOverride,
      ),
    );
  }

  Future<InferenceOutput> _runInFreshSession({
    required String prompt,
    Uint8List? imageBytes,
    required Uint8List? resumedState,
    Future<void> Function(int progressMilli)? onProgress,
    int? maxOutputTokensOverride,
  }) async {
    final model = _runtime.requireModel();
    final stopwatch = Stopwatch()..start();
    final outputTokenCap = maxOutputTokensOverride ?? maxOutputTokens;
    final multimodal = imageBytes != null && imageBytes.isNotEmpty;

    _log(
      '[LLM START] model=${WorkerModelCatalog.displayName} '
      'multimodal=$multimodal promptChars=${prompt.length} '
      'imageBytes=${imageBytes?.length ?? 0}',
    );
    _log('[LLM REQUEST] prompt="${_preview(prompt)}"');

    try {
      await onProgress?.call(resumedState == null ? 100 : 500);

      _log('[LLM SESSION] creating multimodal=$multimodal');
      final chat = await model.createChat(
        temperature: temperature,
        topK: topK,
        topP: topP,
        maxOutputTokens: outputTokenCap,
        supportImage: multimodal,
        modelType: multimodal ? ModelType.gemma4 : null,
        systemInstruction: usePortalPassthroughChat
            ? null
            : 'You are EdgeMint worker AI. '
                  'Answer concisely for the assigned task payload.',
      );
      _log('[LLM SESSION] created');

      try {
        if (multimodal) {
          await chat.addQueryChunk(
            Message.withImage(
              text: prompt,
              imageBytes: imageBytes,
              isUser: true,
            ),
          );
        } else {
          await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
        }
        await onProgress?.call(700);

        _log('[LLM INFERENCE] generation started');
        final generation = await _generateBounded(
          chat,
          maxOutputTokens: outputTokenCap,
        );
        if (stopwatch.isRunning) {
          stopwatch.stop();
        }
        _log(
          '[LLM INFERENCE] generation completed '
          'elapsedMs=${stopwatch.elapsedMilliseconds} '
          'stopReason=${generation.stopReason}',
        );
        await onProgress?.call(1000);

        final text = generation.text;
        _log(
          '[LLM OUTPUT] chars=${text.length} elapsedMs=${stopwatch.elapsedMilliseconds}',
        );
        _log('[LLM RESPONSE] response="${_preview(text)}"');

        return InferenceOutput(
          resultBytes: Uint8List.fromList(utf8.encode(text)),
          progressMilli: 1000,
          metrics: {
            'backend': backend.name,
            'modelProfile': WorkerModelCatalog.profileId,
            'inputBytes': multimodal ? imageBytes.length : utf8.encode(prompt).length,
            'outputChars': text.length,
            'elapsedMs': stopwatch.elapsedMilliseconds,
            'maxTokens': WorkerModelCatalog.runtimeMaxTokens,
            'stopReason': generation.stopReason,
            'sessionStage': multimodal ? 'multimodal' : 'inference',
            'multimodal': multimodal,
          },
        );
      } finally {
        try {
          await chat.session.close();
          _log('[LLM SESSION] closed');
        } catch (error, stackTrace) {
          WorkerPipelineLog.error(
            WorkerPipelineLog.exec,
            '[LLM SESSION] close failed',
            error,
            stackTrace,
          );
        }
      }
    } catch (error, stackTrace) {
      if (stopwatch.isRunning) {
        stopwatch.stop();
      }
      WorkerPipelineLog.error(
        WorkerPipelineLog.exec,
        '[LLM ERROR] elapsedMs=${stopwatch.elapsedMilliseconds}',
        error,
        stackTrace,
      );
      final classified = GemmaLitertMultimodalVisionPolicy.classifyInferenceFailure(
        error,
      );
      if (classified != null) {
        throw classified;
      }
      rethrow;
    }
  }

  /// Streams the reply and stops the native decode as soon as the requested
  /// JSON object closes or the output budget is spent. The MediaPipe `.task`
  /// path ignores `maxOutputTokens`, so without this the model keeps decoding
  /// until it hits the sequence limit and returns truncated, repeated text.
  Future<_BoundedGeneration> _generateBounded(
    InferenceChat chat, {
    int? maxOutputTokens,
  }) async {
    final tokenCap = maxOutputTokens ?? this.maxOutputTokens;
    final maxOutputChars =
        (tokenCap * const TokenEstimator().charactersPerToken).floor();
    final boundary = JsonObjectBoundaryScanner();
    final repetition = OutputRepetitionGuard();
    final buffer = StringBuffer();
    var stopReason = 'model_eos';
    var stopRequested = false;

    await for (final response in chat.generateChatResponseAsync()) {
      // Tokens can still arrive after the stop is requested; the session stays
      // busy until the stream completes, so the loop keeps draining instead of
      // breaking out (closing a busy session throws IllegalStateException).
      if (stopRequested) {
        continue;
      }

      final fragment = switch (response) {
        TextResponse(:final token) => token,
        ThinkingResponse(:final content) => content,
        FunctionCallResponse(:final name, :final args) => '$name($args)',
        ParallelFunctionCallResponse(:final calls) => calls
            .map((call) => '${call.name}(${call.args})')
            .join(', '),
      };
      buffer.write(fragment);

      // Reasoning text is not part of the answer object, so braces inside it
      // must not end the turn early.
      final answerFragment = response is ThinkingResponse ? '' : fragment;
      if (boundary.feed(answerFragment)) {
        stopReason = 'json_complete';
      } else if (buffer.length >= maxOutputChars) {
        stopReason = 'output_limit';
      } else if (repetition.feed(answerFragment)) {
        stopReason = 'repetition';
        _log(
          '[LLM REPETITION STOP] outputChars=${buffer.length} '
          'windowChars=${repetition.windowChars} '
          'minRepeats=${repetition.minRepeats} '
          'localMatches=${repetition.lastTriggerMatchCount} '
          'outputLength=${repetition.lastTriggerOutputLength} '
          'window="${_preview(repetition.lastTriggerWindow ?? '', maxLength: 64)}" '
          'cancelRequested=true',
        );
      } else {
        continue;
      }

      stopRequested = true;
      await _stopGeneration(chat);
    }

    return _BoundedGeneration(text: buffer.toString(), stopReason: stopReason);
  }

  Future<void> _stopGeneration(InferenceChat chat) async {
    try {
      await chat.stopGeneration();
    } catch (error, stackTrace) {
      WorkerPipelineLog.error(
        WorkerPipelineLog.exec,
        '[LLM SESSION] stop failed',
        error,
        stackTrace,
      );
    }
  }

  @override
  Future<void> dispose() {
    return _runtime.unload(
      reason: ModelUnloadReason.lifecycleShutdown,
      force: true,
    );
  }
}
