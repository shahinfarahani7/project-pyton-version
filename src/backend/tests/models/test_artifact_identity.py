"""T16 audit scenarios: artifact/install/runtime identity (P8-A16 / A16)."""

from __future__ import annotations

import pytest

from edgemint.models.artifact_identity import (
    QWEN_MODEL_VERSION_ID,
    QWEN_VERIFIED_CONTEXT_LIMIT,
    ArtifactIdentityManifest,
    evaluate_artifact_identity_consistency,
    load_qwen_artifact_identity_manifest,
    require_consistent_artifact_identity,
)
from edgemint.routing.retry_classifier import RetryClass, classify_failure_code


def test_t16_qwen_manifest_matches_worker_catalog_and_context_profile() -> None:
    manifest = load_qwen_artifact_identity_manifest()
    evaluation = evaluate_artifact_identity_consistency(manifest=manifest)
    assert evaluation.consistent is True
    assert evaluation.reasons == ()
    assert manifest.model_version_id == QWEN_MODEL_VERSION_ID
    assert manifest.verified_context_limit == QWEN_VERIFIED_CONTEXT_LIMIT
    assert "ekv1280" in manifest.artifact_file_name


def test_t16_bad_hash_identity_mismatch_detected() -> None:
    manifest = ArtifactIdentityManifest(
        model_version_id=QWEN_MODEL_VERSION_ID,
        profile_id="qwen2.5-0.5b-artifact",
        artifact_file_name="wrong.task",
        verified_context_limit=QWEN_VERIFIED_CONTEXT_LIMIT,
        runtime_backend="flutter_gemma_mediapipe_v1",
        artifact_evidence="missing",
    )
    evaluation = evaluate_artifact_identity_consistency(manifest=manifest)
    assert evaluation.consistent is False
    assert "ARTIFACT_FILENAME_MISMATCH" in evaluation.reasons
    assert "ARTIFACT_EVIDENCE_MISSING_EKV1280" in evaluation.reasons


def test_t16_require_consistent_identity_raises_on_drift() -> None:
    manifest = ArtifactIdentityManifest(
        model_version_id="mdv_other",
        profile_id="other",
        artifact_file_name="Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task",
        verified_context_limit=4096,
        runtime_backend="flutter_gemma_mediapipe_v1",
        artifact_evidence="ekv4096",
    )
    with pytest.raises(ValueError, match="CONTEXT_LIMIT_MISMATCH"):
        require_consistent_artifact_identity(manifest=manifest)


def test_t16_model_integrity_failure_maps_to_stronger_worker_retry() -> None:
    assert classify_failure_code("MODEL_EXECUTION_FAILED") == RetryClass.STRONGER_WORKER
