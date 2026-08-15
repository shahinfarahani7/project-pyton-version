import 'dart:convert';

import '../contracts/worker_error.dart';

abstract final class JsonOutputValidator {
  static Map<String, dynamic>? parseJsonObject(String raw) {
    final cleaned = _stripMarkdownFences(_stripThinkBlocks(raw.trim()));
    if (cleaned.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      final extracted = _extractFirstJsonObject(cleaned);
      if (extracted != null) {
        try {
          final decoded = jsonDecode(extracted);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
          if (decoded is Map) {
            return Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
      }
    }
    return null;
  }

  static WorkerError? validateSchema(
    Map<String, dynamic> data,
    Map<String, dynamic>? schema,
  ) {
    if (schema == null || schema.isEmpty) {
      return null;
    }
    for (final entry in schema.entries) {
      final key = entry.key;
      if (!data.containsKey(key)) {
        continue;
      }
      final expected = entry.value.toString();
      final value = data[key];
      if (expected.contains('string') && value is! String && value != null) {
        return WorkerError(
          code: WorkerErrorCode.outputSchemaMismatch,
          message: 'Field $key expected string',
          retryable: true,
          stage: WorkerTaskStage.llm,
        );
      }
      if (expected.contains('number') && value is! num && value != null) {
        return WorkerError(
          code: WorkerErrorCode.outputSchemaMismatch,
          message: 'Field $key expected number',
          retryable: true,
          stage: WorkerTaskStage.llm,
        );
      }
    }
    return null;
  }

  static String _stripThinkBlocks(String input) {
    var cleaned = input.replaceAll(
      RegExp(r'<\s*think\s*>[\s\S]*?<\s*/\s*think\s*>', dotAll: true, caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'<think>[\s\S]*?</think>', dotAll: true),
      '',
    );
    return cleaned.trim();
  }

  static String _stripMarkdownFences(String input) {
    if (!input.startsWith('```')) {
      return input;
    }
    final lines = input.split('\n');
    if (lines.length < 2) {
      return input;
    }
    final end = lines.lastWhere((l) => l.trim() == '```', orElse: () => '');
    if (end.isEmpty) {
      return lines.skip(1).join('\n').trim();
    }
    return lines.sublist(1, lines.length - 1).join('\n').trim();
  }

  static String? _extractFirstJsonObject(String input) {
    final start = input.indexOf('{');
    final end = input.lastIndexOf('}');
    if (start < 0 || end <= start) {
      return null;
    }
    return input.substring(start, end + 1);
  }
}
