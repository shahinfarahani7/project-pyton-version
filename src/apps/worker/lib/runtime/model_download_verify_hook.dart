import 'dart:io';
import 'dart:typed_data';

import '../models/worker_model_catalog.dart';
import 'model_artifact_verifier.dart';
import 'runtime_exceptions.dart';

/// Post-download verification hook before model activation (Section 53).
class ModelDownloadVerifyHook {
  const ModelDownloadVerifyHook({
    ModelArtifactVerifier? verifier,
  }) : _verifier = verifier ?? const ModelArtifactVerifier();

  final ModelArtifactVerifier _verifier;

  Future<void> verifyInstalledFile({
    required String path,
    required ModelVerificationPin pin,
    required String signingKey,
    String? modelVersionId,
  }) async {
    if (!pin.isConfigured) {
      throw ModelIntegrityException('Model verification pin is not configured');
    }

    final file = File(path);
    if (!await file.exists()) {
      throw ModelIntegrityException('Downloaded model file is missing');
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw ModelIntegrityException('Downloaded model file is empty');
    }

    _verifier.verifyBytesOrThrow(
      bytes: bytes,
      digestSha256: pin.digestSha256,
      signatureSha256: pin.signatureSha256,
      signingKey: signingKey,
      modelVersionId: modelVersionId,
    );
  }

  Future<void> verifyInstalledFileIfPinned({
    required String path,
    required String signingKey,
    String? modelVersionId,
  }) async {
    final pin = WorkerModelCatalog.verificationPin();
    if (pin == null) {
      return;
    }
    await verifyInstalledFile(
      path: path,
      pin: pin,
      signingKey: signingKey,
      modelVersionId: modelVersionId,
    );
  }
}
