import 'dart:typed_data';

import 'package:edgemint_worker/api/worker_assignment_models.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/runtime/failure_evidence.dart';
import 'package:edgemint_worker/runtime/inference_adapter.dart';
import 'package:edgemint_worker/runtime/model_artifact_verifier.dart';
import 'package:edgemint_worker/runtime/runtime_exceptions.dart';
import 'package:edgemint_worker/api/worker_assignment_models.dart';
import 'package:edgemint_worker/models/worker_model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _modelBytes() => Uint8List.fromList('signed-model-bytes'.codeUnits);

ModelArtifact _signedArtifact({
  required String signingKey,
  String signatureSha256 = '',
}) {
  final digest = sha256Hex(_modelBytes());
  return ModelArtifact(
    modelVersionId: WorkerModelCatalog.modelVersionId,
    digestSha256: digest,
    signatureSha256: signatureSha256.isEmpty
        ? sha256HexString('$digest:${WorkerModelCatalog.modelVersionId}:$signingKey')
        : signatureSha256,
    backend: InferenceBackend.liteRt,
    bytes: _modelBytes(),
  );
}

void main() {
  const signingKey = 'device-signing-material';
  const verifier = ModelArtifactVerifier();

  test('accepts artifact with matching digest and signature', () {
    expect(
      () => verifier.verifyOrThrow(
        artifact: _signedArtifact(signingKey: signingKey),
        signingKey: signingKey,
      ),
      returnsNormally,
    );
  });

  test('rejects unsigned artifact with empty signature', () {
    final artifact = _signedArtifact(signingKey: signingKey, signatureSha256: '   ');
    expect(
      () => verifier.verifyOrThrow(artifact: artifact, signingKey: signingKey),
      throwsA(isA<ModelIntegrityException>()),
    );
  });

  test('rejects artifact with bad signature fixture', () {
    final artifact = _signedArtifact(
      signingKey: signingKey,
      signatureSha256: 'a' * 64,
    );
    expect(
      () => verifier.verifyOrThrow(artifact: artifact, signingKey: signingKey),
      throwsA(
        predicate<ModelIntegrityException>(
          (error) => error.reason.contains('signature'),
        ),
      ),
    );
  });

  test('rejects corrupted artifact bytes', () {
    final artifact = _signedArtifact(signingKey: signingKey);
    final corrupted = ModelArtifact(
      modelVersionId: artifact.modelVersionId,
      digestSha256: artifact.digestSha256,
      signatureSha256: artifact.signatureSha256,
      backend: artifact.backend,
      bytes: Uint8List.fromList([0, 1, 2]),
    );
    expect(
      () => verifier.verifyOrThrow(artifact: corrupted, signingKey: signingKey),
      throwsA(
        predicate<ModelIntegrityException>(
          (error) => error.reason.contains('digest mismatch'),
        ),
      ),
    );
  });

  test('rejects bare installed marker signature as unsigned', () {
    expect(
      () => verifier.verifyOrThrow(
        artifact: ModelArtifact(
          modelVersionId: WorkerModelCatalog.modelVersionId,
          digestSha256: WorkerModelCatalog.installedDigestMarker,
          signatureSha256: WorkerModelCatalog.installedDigestMarker,
          backend: InferenceBackend.liteRt,
          bytes: Uint8List.fromList([0]),
        ),
        signingKey: signingKey,
      ),
      throwsA(
        predicate<ModelIntegrityException>(
          (error) => error.reason.contains('Unsigned'),
        ),
      ),
    );
  });

  test('accepts installed marker with device attestation signature', () {
    expect(
      () => verifier.verifyOrThrow(
        artifact: ModelArtifact(
          modelVersionId: WorkerModelCatalog.modelVersionId,
          digestSha256: WorkerModelCatalog.installedDigestMarker,
          signatureSha256: WorkerModelCatalog.installedAttestationSignature(signingKey),
          backend: InferenceBackend.liteRt,
          bytes: Uint8List.fromList([0]),
        ),
        signingKey: signingKey,
      ),
      returnsNormally,
    );
  });

  test('maps model integrity failures to execution failure evidence', () {
    const mapper = FailureEvidenceMapper();
    final evidence = mapper.map(
      assignment: WorkerAssignment(
        assignmentId: 'asg-1',
        attemptId: 'att-1',
        revisionId: 'rev-1',
        leaseToken: 'lease-token-1234567890',
        fenceToken: 2,
        leaseExpiresAt: DateTime.parse('2026-12-01T00:00:00Z'),
        taskType: 'text.summarize',
        modelVersionId: WorkerModelCatalog.modelVersionId,
        inputManifestUrl: 'https://example/input',
        outputUploadUrl: 'https://example/output',
        startDeadlineAt: DateTime.parse('2026-11-30T00:00:00Z'),
      ),
      error: ModelIntegrityException('Model digest mismatch'),
      executionTime: Duration.zero,
    );

    expect(evidence?.failureCode, ClosedFailureCode.modelExecutionFailed);
    expect(evidence?.retryable, isTrue);
  });
}
