import 'dart:typed_data';

import 'inference_adapter.dart';

/// Swaps the active inference backend (real LiteRT vs dev mock).
class SwitchableInferenceAdapter implements InferenceAdapter {
  SwitchableInferenceAdapter(this._active);

  InferenceAdapter _active;

  void use(InferenceAdapter adapter) {
    _active = adapter;
  }

  InferenceAdapter get active => _active;

  @override
  InferenceBackend get backend => _active.backend;

  @override
  Future<void> loadVerified(ModelArtifact artifact, {required String signingKey}) {
    return _active.loadVerified(artifact, signingKey: signingKey);
  }

  @override
  Future<InferenceOutput> run({
    required Uint8List inputBytes,
    required Uint8List? resumedState,
    Future<void> Function(int progressMilli)? onProgress,
  }) async {
    final output = await _active.run(
      inputBytes: inputBytes,
      resumedState: resumedState,
      onProgress: onProgress,
    );
    lastOutput = output;
    return output;
  }

  InferenceOutput? lastOutput;

  @override
  Future<void> dispose() {
    return _active.dispose();
  }
}
