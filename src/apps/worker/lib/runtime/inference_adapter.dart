import 'dart:convert';
import 'dart:typed_data';

import 'encrypted_store.dart';
import 'runtime_exceptions.dart';
import 'model_artifact_verifier.dart';

enum InferenceBackend { onnx, liteRt, stub }

class ModelArtifact {
  const ModelArtifact({
    required this.modelVersionId,
    required this.digestSha256,
    required this.signatureSha256,
    required this.backend,
    required this.bytes,
  });

  final String modelVersionId;
  final String digestSha256;
  final String signatureSha256;
  final InferenceBackend backend;
  final Uint8List bytes;
}

class InferenceOutput {
  const InferenceOutput({
    required this.resultBytes,
    required this.progressMilli,
    required this.metrics,
  });

  final Uint8List resultBytes;
  final int progressMilli;
  final Map<String, dynamic> metrics;
}

abstract class InferenceAdapter {
  InferenceBackend get backend;

  Future<void> loadVerified(ModelArtifact artifact, {required String signingKey});

  Future<InferenceOutput> run({
    required Uint8List inputBytes,
    required Uint8List? resumedState,
    Future<void> Function(int progressMilli)? onProgress,
  });

  Future<void> dispose();
}

class StubInferenceAdapter implements InferenceAdapter {
  StubInferenceAdapter({this.backend = InferenceBackend.stub});

  @override
  final InferenceBackend backend;

  ModelArtifact? _loaded;

  @override
  Future<void> loadVerified(ModelArtifact artifact, {required String signingKey}) async {
    const ModelArtifactVerifier().verifyOrThrow(
      artifact: artifact,
      signingKey: signingKey,
    );
    _loaded = artifact;
  }

  @override
  Future<InferenceOutput> run({
    required Uint8List inputBytes,
    required Uint8List? resumedState,
    Future<void> Function(int progressMilli)? onProgress,
  }) async {
    if (_loaded == null) {
      throw StateError('Model not loaded');
    }
    final start = resumedState == null ? 0 : 500;
    for (var progress = start; progress <= 1000; progress += 250) {
      await onProgress?.call(progress);
    }
    final prefix = resumedState == null ? 'fresh' : 'resumed';
    final resultBytes = Uint8List.fromList('$prefix:${utf8.decode(inputBytes)}'.codeUnits);
    return InferenceOutput(
      resultBytes: resultBytes,
      progressMilli: 1000,
      metrics: {'backend': backend.name, 'inputBytes': inputBytes.length},
    );
  }

  @override
  Future<void> dispose() async {
    _loaded = null;
  }
}

class OnnxInferenceAdapter extends StubInferenceAdapter {
  OnnxInferenceAdapter() : super(backend: InferenceBackend.onnx);
}

class LiteRtInferenceAdapter extends StubInferenceAdapter {
  LiteRtInferenceAdapter() : super(backend: InferenceBackend.liteRt);
}
