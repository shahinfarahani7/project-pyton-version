import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/worker_model_artifact_descriptor.dart';
import 'runtime_exceptions.dart';

/// Result of pre-native compatibility validation.
class WorkerModelFormatValidation {
  const WorkerModelFormatValidation._({
    required this.accepted,
    required this.reasonCode,
    this.detail,
    this.detectedSourceFormat,
  });

  const WorkerModelFormatValidation.accepted({
    WorkerModelSourceFormat? detectedSourceFormat,
  }) : this._(
          accepted: true,
          reasonCode: 'OK',
          detectedSourceFormat: detectedSourceFormat,
        );

  const WorkerModelFormatValidation.rejected({
    required String reasonCode,
    required String detail,
    WorkerModelSourceFormat? detectedSourceFormat,
  }) : this._(
          accepted: false,
          reasonCode: reasonCode,
          detail: detail,
          detectedSourceFormat: detectedSourceFormat,
        );

  final bool accepted;
  final String reasonCode;
  final String? detail;
  final WorkerModelSourceFormat? detectedSourceFormat;
}

/// Fails fast before LiteRT native load when an artifact is not runnable.
abstract final class WorkerModelFormatGate {
  static const minLitertLmBytes = 3_000_000_000;
  static const maxHeaderProbeBytes = 65536;

  static WorkerModelFormatValidation validateForRuntime({
    required WorkerModelArtifactDescriptor expected,
    required String filePath,
    int? fileSizeBytes,
  }) {
    if (!expected.isRuntimeReady) {
      return const WorkerModelFormatValidation.rejected(
        reasonCode: 'MODEL_FORMAT_UNSUPPORTED',
        detail: 'Descriptor is not runtime-ready',
      );
    }

    final lower = filePath.toLowerCase();
    final size = fileSizeBytes;

    if (lower.endsWith('.safetensors')) {
      return const WorkerModelFormatValidation.rejected(
        reasonCode: 'MODEL_FORMAT_UNSUPPORTED',
        detail:
            'Safetensors QAT checkpoints are source weights, not LiteRT-LM runtime packages',
        detectedSourceFormat: WorkerModelSourceFormat.safetensorsQat,
      );
    }

    if (expected.runtimeFormat == WorkerModelRuntimeFormat.litertLm) {
      if (!lower.endsWith('.litertlm')) {
        return WorkerModelFormatValidation.rejected(
          reasonCode: 'MODEL_FORMAT_UNSUPPORTED',
          detail: 'Expected .litertlm runtime artifact, got $filePath',
        );
      }
      if (size != null && size < minLitertLmBytes) {
        return WorkerModelFormatValidation.rejected(
          reasonCode: 'MODEL_FORMAT_UNSUPPORTED',
          detail: 'LiteRT-LM artifact too small ($size bytes)',
        );
      }
    }

    return const WorkerModelFormatValidation.accepted(
      detectedSourceFormat: WorkerModelSourceFormat.litertLm,
    );
  }

  static Future<WorkerModelFormatValidation> validateFileOnDisk({
    required WorkerModelArtifactDescriptor expected,
    required String filePath,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return WorkerModelFormatValidation.rejected(
        reasonCode: 'MODEL_ARTIFACT_MISSING',
        detail: filePath,
      );
    }

    final size = await file.length();
    final head = await _readHead(file, maxHeaderProbeBytes);
    if (_looksLikeSafetensors(head)) {
      return const WorkerModelFormatValidation.rejected(
        reasonCode: 'MODEL_FORMAT_UNSUPPORTED',
        detail:
            'File content is Hugging Face safetensors (QAT packed weights), not LiteRT-LM',
        detectedSourceFormat: WorkerModelSourceFormat.safetensorsQat,
      );
    }

    return validateForRuntime(
      expected: expected,
      filePath: filePath,
      fileSizeBytes: size,
    );
  }

  static Future<WorkerModelFormatValidation> validateBundledAssetPath(
    String assetPath,
  ) async {
    final lower = assetPath.toLowerCase();
    if (lower.endsWith('.safetensors')) {
      return const WorkerModelFormatValidation.rejected(
        reasonCode: 'MODEL_FORMAT_UNSUPPORTED',
        detail:
            'Bundled safetensors cannot be registered as LiteRT-LM; use download/sideload of .litertlm',
        detectedSourceFormat: WorkerModelSourceFormat.safetensorsQat,
      );
    }
    if (!lower.endsWith('.litertlm')) {
      return WorkerModelFormatValidation.rejected(
        reasonCode: 'MODEL_FORMAT_UNSUPPORTED',
        detail: 'Bundled asset must be .litertlm for runtime install',
      );
    }
    return const WorkerModelFormatValidation.accepted(
      detectedSourceFormat: WorkerModelSourceFormat.litertLm,
    );
  }

  static void ensureAcceptedOrThrow(WorkerModelFormatValidation validation) {
    if (validation.accepted) {
      return;
    }
    throw ModelFormatUnsupportedException(
      validation.reasonCode,
      validation.detail ?? validation.reasonCode,
    );
  }

  static bool _looksLikeSafetensors(Uint8List head) {
    if (head.length < 12) {
      return false;
    }
    try {
      final headerLen = ByteData.sublistView(head, 0, 8).getUint64(0, Endian.little);
      if (headerLen <= 0 || headerLen > maxHeaderProbeBytes - 8) {
        return false;
      }
      final jsonText = utf8.decode(head.sublist(8, 8 + headerLen));
      if (!jsonText.trimLeft().startsWith('{')) {
        return false;
      }
      return jsonText.contains('"dtype"') &&
          (jsonText.contains('weight_scale') ||
              jsonText.contains('input_activation_scale'));
    } catch (_) {
      return false;
    }
  }

  static Future<Uint8List> _readHead(File file, int maxBytes) async {
    final raf = await file.open();
    try {
      final length = await raf.length();
      final toRead = length < maxBytes ? length : maxBytes;
      return await raf.read(toRead);
    } finally {
      await raf.close();
    }
  }

  /// Probes a local QAT safetensors source (evaluation only; never native load).
  static Future<WorkerModelFormatValidation> probeQatSourceFile(
    String filePath,
  ) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return WorkerModelFormatValidation.rejected(
        reasonCode: 'QAT_SOURCE_MISSING',
        detail: filePath,
      );
    }
    final head = await _readHead(file, maxHeaderProbeBytes);
    if (!_looksLikeSafetensors(head)) {
      return const WorkerModelFormatValidation.rejected(
        reasonCode: 'QAT_SOURCE_INVALID',
        detail: 'Not a Gemma QAT packed safetensors header',
      );
    }
    return const WorkerModelFormatValidation.accepted(
      detectedSourceFormat: WorkerModelSourceFormat.safetensorsQat,
    );
  }
}
