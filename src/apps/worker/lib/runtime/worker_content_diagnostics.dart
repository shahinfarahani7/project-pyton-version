import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'worker_pipeline_log.dart';

/// Opt-in development logging for complete task/prompt/response payloads.
///
/// Enable with: `--dart-define=WORKER_VERBOSE_TASK_CONTENT=true`
abstract final class WorkerContentDiagnostics {
  static const enabled = bool.fromEnvironment(
    'WORKER_VERBOSE_TASK_CONTENT',
    defaultValue: false,
  );

  /// Keeps each log line under typical Android logcat limits.
  static const maxPartChars = 800;

  static String sha256Hex(String? value) {
    if (value == null || value.isEmpty) {
      return 'empty';
    }
    return sha256.convert(utf8.encode(value)).toString();
  }

  static void logText({
    required String label,
    String? content,
    Map<String, String>? metadata,
  }) {
    if (!enabled) {
      return;
    }
    final text = content ?? '';
    final utf8Bytes = utf8.encode(text).length;
    final meta = metadata == null || metadata.isEmpty
        ? ''
        : ' ${metadata.entries.map((e) => '${e.key}=${e.value}').join(' ')}';
    final parts = text.isEmpty
        ? 1
        : ((text.length + maxPartChars - 1) ~/ maxPartChars);
    WorkerPipelineLog.info(
      WorkerPipelineLog.exec,
      '[$label BEGIN]$meta parts=$parts chars=${text.length} utf8Bytes=$utf8Bytes '
      'sha256=${sha256Hex(text)}',
    );
    if (text.isEmpty) {
      WorkerPipelineLog.info(
        WorkerPipelineLog.exec,
        '[$label PART 1/1] (empty)',
      );
    } else {
      for (var index = 0; index < parts; index++) {
        final start = index * maxPartChars;
        final end = (start + maxPartChars).clamp(0, text.length);
        WorkerPipelineLog.info(
          WorkerPipelineLog.exec,
          '[$label PART ${index + 1}/$parts] ${text.substring(start, end)}',
        );
      }
    }
    WorkerPipelineLog.info(
      WorkerPipelineLog.exec,
      '[$label END] chars=${text.length} utf8Bytes=$utf8Bytes '
      'sha256=${sha256Hex(text)}',
    );
  }

  static void logInferencePrompt({
    required String stage,
    int? chunkIndex,
    int? totalChunks,
    required String prompt,
  }) {
    if (!enabled) {
      return;
    }
    final chunkMeta = chunkIndex == null
        ? ''
        : ' chunk=${chunkIndex + 1}/${totalChunks ?? '?'}';
    logText(
      label: 'INFERENCE PROMPT $stage$chunkMeta',
      content: prompt,
    );
  }

  static void logInferenceResponse({
    required String stage,
    int? chunkIndex,
    int? totalChunks,
    required String raw,
    required String stopReason,
    required bool truncated,
  }) {
    if (!enabled) {
      return;
    }
    final chunkMeta = chunkIndex == null
        ? ''
        : ' chunk=${chunkIndex + 1}/${totalChunks ?? '?'}';
    logText(
      label: 'INFERENCE RESPONSE $stage$chunkMeta',
      content: raw,
      metadata: {
        'stopReason': stopReason,
        'truncated': truncated.toString(),
      },
    );
  }
}
