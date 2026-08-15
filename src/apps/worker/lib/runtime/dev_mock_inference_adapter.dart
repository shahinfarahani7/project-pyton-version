import 'dart:convert';
import 'dart:typed_data';

import '../models/worker_model_catalog.dart';
import 'inference_adapter.dart';
import 'runtime_exceptions.dart';

/// Dev-only inference for x86 Android emulators (MEmu/LDPlayer).
/// LiteRT-LM `.litertlm` models require arm64-v8a and cannot run on x86_64.
class DevMockInferenceAdapter implements InferenceAdapter {
  @override
  InferenceBackend get backend => InferenceBackend.liteRt;

  bool _loaded = false;
  String? _taskTypeHint;

  void setTaskTypeHint(String? taskType) {
    _taskTypeHint = taskType;
  }

  @override
  Future<void> loadVerified(ModelArtifact artifact, {required String signingKey}) async {
    if (artifact.digestSha256 != WorkerModelCatalog.installedDigestMarker &&
        artifact.modelVersionId != WorkerModelCatalog.modelVersionId) {
      throw ModelIntegrityException('Unexpected model version for dev mock');
    }
    _loaded = true;
  }

  @override
  Future<InferenceOutput> run({
    required Uint8List inputBytes,
    required Uint8List? resumedState,
    Future<void> Function(int progressMilli)? onProgress,
  }) async {
    if (!_loaded) {
      throw StateError('Dev mock model not loaded');
    }
    await onProgress?.call(200);

    if (_taskTypeHint == 'image.remove_background' || _looksLikeImage(inputBytes)) {
      final summary =
          'Background removed (dev-mock on x86 — returns processed PNG; use ARM64 for real Qwen3)';
      await onProgress?.call(1000);
      return InferenceOutput(
        resultBytes: inputBytes,
        progressMilli: 1000,
        metrics: {
          'backend': 'dev-mock',
          'modelProfile': WorkerModelCatalog.profileId,
          'outputKind': 'image',
          'outputMimeType': 'image/png',
          'resultSummary': summary,
          'note': 'x86 emulator — LiteRT-LM requires arm64-v8a',
        },
      );
    }

    final prompt = utf8.decode(inputBytes);
    final payload = _extractCustomerPayload(prompt);
    final result = _resultForPrompt(prompt, payload);
    await onProgress?.call(1000);
    return InferenceOutput(
      resultBytes: Uint8List.fromList(utf8.encode(result)),
      progressMilli: 1000,
      metrics: {
        'backend': 'dev-mock',
        'modelProfile': WorkerModelCatalog.profileId,
        'outputKind': 'text',
        'note': 'x86 emulator — LiteRT-LM requires arm64-v8a',
      },
    );
  }

  bool _looksLikeImage(Uint8List bytes) {
    if (bytes.length >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      return true;
    }
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return true;
    }
    return false;
  }

  String _extractCustomerPayload(String prompt) {
    final marker = '\n\n';
    final index = prompt.lastIndexOf(marker);
    if (index >= 0 && index + marker.length < prompt.length) {
      var body = prompt.substring(index + marker.length).trim();
      const userNote = 'User note:';
      final noteIndex = body.indexOf(userNote);
      if (noteIndex >= 0) {
        body = body.substring(0, noteIndex).trim();
      }
      if (body.isNotEmpty) {
        return body;
      }
    }
    return prompt.trim();
  }

  String _resultForPrompt(String prompt, String payload) {
    final lower = prompt.toLowerCase();
    if (lower.contains('summarize')) {
      final snippet = payload.length > 180 ? '${payload.substring(0, 180)}…' : payload;
      return 'Summary: $snippet\n\n[dev-mock summarize on x86 — use ARM64 for real Qwen3]';
    }
    if (lower.contains('ocr') || lower.contains('extract every line')) {
      return '$payload\n\n[dev-mock OCR on x86 emulator — use ARM64 device for real Qwen3 inference]';
    }
    if (lower.contains('classify')) {
      final label = _guessCategory(payload);
      return 'Category: $label\nReason: based on customer upload metadata.\n\n[dev-mock classify on x86 — use ARM64 for real Qwen3]';
    }
    return '[dev-mock] $payload';
  }

  String _guessCategory(String payload) {
    final lower = payload.toLowerCase();
    if (lower.contains('invoice') || lower.contains('receipt')) {
      return 'finance-document';
    }
    if (lower.contains('warehouse') || lower.contains('shelf') || lower.contains('sku')) {
      return 'retail-inventory';
    }
    if (lower.contains('photo') || lower.contains('image') || lower.contains('.jpg') || lower.contains('.png')) {
      return 'general-photo';
    }
    final firstLine = payload.split('\n').firstWhere((line) => line.trim().isNotEmpty, orElse: () => 'general');
    return firstLine.trim().length > 48 ? '${firstLine.trim().substring(0, 48)}…' : firstLine.trim();
  }

  @override
  Future<void> dispose() async {
    _loaded = false;
    _taskTypeHint = null;
  }
}
