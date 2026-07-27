from __future__ import annotations

import pytest
from edgemint.building_blocks.settings import Settings
from edgemint.models.compatibility import (
    DeviceResourceSnapshot,
    ModelResourceEnvelope,
    assert_device_compatible,
)
from edgemint.models.distribution import admit_chunk_download, reject_downgrade
from edgemint.models.errors import ModelServiceError
from edgemint.models.lifecycle import ModelDownloadLifecycle, ModelVersionLifecycle
from edgemint.models.promotion import ReleaseEvidence, validate_promotion_gate
from edgemint.models.signing import build_digest_pinned_manifest, verify_manifest_signature


def test_version_lifecycle_allows_draft_to_active() -> None:
    lifecycle = ModelVersionLifecycle.load()
    assert lifecycle.can_transition("draft", "active")


def test_download_lifecycle_matches_dsl() -> None:
    lifecycle = ModelDownloadLifecycle.load()
    assert lifecycle.can_transition("downloading", "verifying")
    assert lifecycle.can_transition("verifying", "installed")


def test_promotion_gate_requires_benchmark_and_rollback() -> None:
    manifest, signature = build_digest_pinned_manifest(
        model_version_public_id="mdv_test",
        artifact_sha256="a" * 64,
        artifact_size_bytes=1024,
        runtime_abi="onnxruntime-1.18",
        license_spdx="Apache-2.0",
        chunk_size_bytes=512,
    )
    evidence = ReleaseEvidence(
        artifact_sha256="a" * 64,
        signature_sha256=signature,
        license_spdx="Apache-2.0",
        license_status="approved",
        benchmark_evidence_path=None,
        rollback_version_id=None,
        manifest=manifest,
    )
    with pytest.raises(ModelServiceError) as exc:
        validate_promotion_gate(evidence)
    assert exc.value.code == "MODEL_RELEASE_EVIDENCE_MISSING"


def test_promotion_gate_accepts_complete_evidence() -> None:
    manifest, signature = build_digest_pinned_manifest(
        model_version_public_id="mdv_test",
        artifact_sha256="b" * 64,
        artifact_size_bytes=2048,
        runtime_abi="onnxruntime-1.18",
        license_spdx="MIT",
        chunk_size_bytes=1024,
    )
    evidence = ReleaseEvidence(
        artifact_sha256="b" * 64,
        signature_sha256=signature,
        license_spdx="MIT",
        license_status="approved",
        benchmark_evidence_path="evidence/actual/models/sample.json",
        rollback_version_id="mdv_prev",
        manifest=manifest,
    )
    validate_promotion_gate(evidence, settings=Settings(model_approved_licenses="MIT,Apache-2.0"))


def test_manifest_signature_verification() -> None:
    manifest, signature = build_digest_pinned_manifest(
        model_version_public_id="mdv_test",
        artifact_sha256="c" * 64,
        artifact_size_bytes=4096,
        runtime_abi="onnxruntime-1.18",
        license_spdx="Apache-2.0",
        chunk_size_bytes=2048,
    )
    verify_manifest_signature(manifest, signature_sha256=signature)
    with pytest.raises(ModelServiceError) as exc:
        verify_manifest_signature(manifest, signature_sha256="d" * 64)
    assert exc.value.code == "MODEL_SIGNATURE_INVALID"


def test_chunk_replay_is_rejected() -> None:
    with pytest.raises(ModelServiceError) as exc:
        admit_chunk_download(
            last_chunk_index=0,
            chunk_index=0,
            chunk_sha256="abc",
            expected_sha256="abc",
        )
    assert exc.value.code == "MODEL_DIGEST_MISMATCH"


def test_corrupt_chunk_is_rejected() -> None:
    with pytest.raises(ModelServiceError) as exc:
        admit_chunk_download(
            last_chunk_index=-1,
            chunk_index=0,
            chunk_sha256="bad",
            expected_sha256="good",
        )
    assert exc.value.code == "MODEL_DIGEST_MISMATCH"


def test_downgrade_is_blocked() -> None:
    with pytest.raises(ModelServiceError):
        reject_downgrade(installed_version_rank=5, candidate_version_rank=3)


def test_device_compatibility_enforces_tier_and_ram() -> None:
    device = DeviceResourceSnapshot(
        device_tier="C",
        runtime_abi="onnxruntime-1.18",
        free_ram_bytes=512,
        free_storage_bytes=10_000_000,
    )
    envelope = ModelResourceEnvelope(
        minimum_device_tier="T2",
        runtime_abi="onnxruntime-1.18",
        peak_ram_bytes=1024,
        minimum_free_storage_bytes=1_000_000,
    )
    with pytest.raises(ModelServiceError) as exc:
        assert_device_compatible(device, envelope)
    assert exc.value.code == "MODEL_NOT_COMPATIBLE"

    compatible = ModelResourceEnvelope(
        minimum_device_tier="T1",
        runtime_abi="onnxruntime-1.18",
        peak_ram_bytes=256,
        minimum_free_storage_bytes=1_000_000,
    )
    assert_device_compatible(device, compatible)
