import 'dart:typed_data';

import '../models/worker_model_catalog.dart';
import 'encrypted_store.dart';
import 'inference_adapter.dart';
import 'runtime_exceptions.dart';

class ModelVerificationPin {
  const ModelVerificationPin({
    required this.digestSha256,
    required this.signatureSha256,
  });

  final String digestSha256;
  final String signatureSha256;

  bool get isConfigured =>
      digestSha256.trim().isNotEmpty && signatureSha256.trim().isNotEmpty;
}

/// SHA256 + signature verification for model artifacts (Architecture Section 53).
class ModelArtifactVerifier {
  const ModelArtifactVerifier();

  void verifyOrThrow({
    required ModelArtifact artifact,
    required String signingKey,
  }) {
    verifyBytesOrThrow(
      bytes: artifact.bytes,
      digestSha256: artifact.digestSha256,
      signatureSha256: artifact.signatureSha256,
      signingKey: signingKey,
      modelVersionId: artifact.modelVersionId,
    );
  }

  void verifyBytesOrThrow({
    required Uint8List bytes,
    required String digestSha256,
    required String signatureSha256,
    required String signingKey,
    String? modelVersionId,
  }) {
    if (signatureSha256.trim().isEmpty) {
      throw ModelIntegrityException('Model signature missing');
    }
    if (!_isSha256Hex(digestSha256) &&
        digestSha256 != WorkerModelCatalog.installedDigestMarker) {
      throw ModelIntegrityException('Model digest invalid');
    }

    if (digestSha256 == WorkerModelCatalog.installedDigestMarker) {
      _verifyInstalledAttestation(
        signatureSha256: signatureSha256,
        signingKey: signingKey,
      );
      return;
    }

    final actualDigest = sha256Hex(bytes);
    if (actualDigest != digestSha256) {
      throw ModelIntegrityException('Model digest mismatch');
    }

    final expectedSignature = _expectedSignature(
      digestSha256: digestSha256,
      signingKey: signingKey,
      modelVersionId: modelVersionId,
    );
    if (expectedSignature != signatureSha256) {
      throw ModelIntegrityException('Model signature invalid');
    }
  }

  void _verifyInstalledAttestation({
    required String signatureSha256,
    required String signingKey,
  }) {
    if (signatureSha256 == WorkerModelCatalog.installedDigestMarker) {
      throw ModelIntegrityException('Unsigned installed model rejected');
    }
    final expected = WorkerModelCatalog.installedAttestationSignature(signingKey);
    if (signatureSha256 != expected) {
      throw ModelIntegrityException('Installed model attestation invalid');
    }
  }

  static String _expectedSignature({
    required String digestSha256,
    required String signingKey,
    String? modelVersionId,
  }) {
    if (modelVersionId != null && modelVersionId.isNotEmpty) {
      return sha256HexString('$digestSha256:$modelVersionId:$signingKey');
    }
    return sha256HexString('$digestSha256:$signingKey');
  }

  static bool _isSha256Hex(String value) =>
      value.length == 64 && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
}
