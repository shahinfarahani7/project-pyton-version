import 'dart:io';

import 'package:edgemint_worker/models/worker_model_catalog.dart';
import 'package:edgemint_worker/runtime/worker_model_format_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkerModelFormatGate', () {
    test('accepts Gemma4 litertlm runtime path by metadata', () {
      expect(
        WorkerModelFormatGate.validateForRuntime(
          expected: WorkerModelCatalog.generalRuntimeDescriptor,
          filePath: '/data/app/gemma-4-E4B-it.litertlm',
          fileSizeBytes: WorkerModelFormatGate.minLitertLmBytes + 1,
        ).accepted,
        isTrue,
      );
    });

    test('accepts Gemma4 GPU litertlm filename by metadata', () {
      expect(
        WorkerModelFormatGate.validateForRuntime(
          expected: WorkerModelCatalog.gpuRuntimeDescriptor,
          filePath: '/data/app/gemma-4-E4B-it-gpu.litertlm',
          fileSizeBytes: WorkerModelFormatGate.minLitertLmBytes + 1,
        ).accepted,
        isTrue,
      );
    });

    test('rejects safetensors extension before native load', () {
      final result = WorkerModelFormatGate.validateForRuntime(
        expected: WorkerModelCatalog.activeRuntimeDescriptor,
        filePath: '/data/app/model.safetensors',
        fileSizeBytes: 3_500_000_000,
      );
      expect(result.accepted, isFalse);
      expect(result.reasonCode, 'MODEL_FORMAT_UNSUPPORTED');
    });

    test('rejects safetensors content even when renamed to litertlm', () async {
      final dir = await Directory.systemTemp.createTemp('edgemint_format_gate');
      final fake = File('${dir.path}/fake.litertlm');
      // Minimal safetensors header with QAT scale tensors.
      final header = r'{"tensor":{"dtype":"F32","shape":[],"data_offsets":[0,4]}}';
      final headerBytes = header.codeUnits;
      final len = headerBytes.length;
      final bytes = <int>[
        len & 0xff,
        (len >> 8) & 0xff,
        (len >> 16) & 0xff,
        (len >> 24) & 0xff,
        0,
        0,
        0,
        0,
        ...headerBytes,
      ];
      await fake.writeAsBytes(bytes, flush: true);

      final validation = await WorkerModelFormatGate.validateFileOnDisk(
        expected: WorkerModelCatalog.activeRuntimeDescriptor,
        filePath: fake.path,
      );
      expect(validation.accepted, isFalse);
      expect(validation.reasonCode, 'MODEL_FORMAT_UNSUPPORTED');
      await dir.delete(recursive: true);
    });

    test('rejects bundled safetensors asset path', () async {
      final validation = await WorkerModelFormatGate.validateBundledAssetPath(
        'assets/models/model.safetensors',
      );
      expect(validation.accepted, isFalse);
      expect(validation.reasonCode, 'MODEL_FORMAT_UNSUPPORTED');
    });

    test('QAT source probe accepts packed safetensors header', () async {
      final dir = await Directory.systemTemp.createTemp('edgemint_qat_probe');
      final file = File('${dir.path}/model.safetensors');
      final header =
          r'{"layer.weight_scale":{"dtype":"F32","shape":[1,1],"data_offsets":[0,4]}}';
      final headerBytes = header.codeUnits;
      final len = headerBytes.length;
      await file.writeAsBytes(
        [
          len & 0xff,
          (len >> 8) & 0xff,
          (len >> 16) & 0xff,
          (len >> 24) & 0xff,
          0,
          0,
          0,
          0,
          ...headerBytes,
        ],
        flush: true,
      );
      final probe = await WorkerModelFormatGate.probeQatSourceFile(file.path);
      expect(probe.accepted, isTrue);
      await dir.delete(recursive: true);
    });
  });
}
