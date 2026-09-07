from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from edgemint.workers.checkpoint_resume import (
    CheckpointResumeService,
    ResumeCompatibilityDecision,
    evaluate_resume_compatibility,
)
from edgemint.workers.errors import WorkerServiceError


def _base_kwargs(**overrides: object) -> dict[str, object]:
    defaults: dict[str, object] = {
        "manifest_model_version_id": "mdv-qwen",
        "manifest_runtime_version": "flutter_gemma_mediapipe_v1",
        "manifest_prompt_template_version": "1.0",
        "manifest_execution_plan_version": "2026-q3-v1",
        "manifest_input_digest": "a" * 64,
        "manifest_validation_status": "accepted",
        "grant_model_version_id": "mdv-qwen",
        "grant_runtime_version": "flutter_gemma_mediapipe_v1",
        "grant_prompt_template_version": "1.0",
        "grant_execution_plan_version": "2026-q3-v1",
        "grant_input_digest": "a" * 64,
        "grant_expires_at_utc": datetime.now(UTC) + timedelta(hours=1),
        "requested_chunk_ids": ("chunk-0",),
        "authorized_chunk_ids": ("chunk-0", "chunk-1"),
    }
    defaults.update(overrides)
    return defaults


def test_evaluate_resume_compatibility_accepts_matching_manifest_and_grant() -> None:
    result = evaluate_resume_compatibility(**_base_kwargs())
    assert result.permitted is True
    assert result.decision == ResumeCompatibilityDecision.COMPATIBLE


def test_evaluate_resume_compatibility_rejects_expired_grant() -> None:
    result = evaluate_resume_compatibility(
        **_base_kwargs(
            grant_expires_at_utc=datetime.now(UTC) - timedelta(minutes=1),
        )
    )
    assert result.permitted is False
    assert result.decision == ResumeCompatibilityDecision.GRANT_EXPIRED


def test_evaluate_resume_compatibility_rejects_model_space_mismatch() -> None:
    result = evaluate_resume_compatibility(
        **_base_kwargs(grant_model_version_id="mdv-other"),
    )
    assert result.permitted is False
    assert result.decision == ResumeCompatibilityDecision.INCOMPATIBLE_MODEL_SPACE


def test_evaluate_resume_compatibility_rejects_unauthorized_chunk() -> None:
    result = evaluate_resume_compatibility(
        **_base_kwargs(
            requested_chunk_ids=("chunk-9",),
            authorized_chunk_ids=("chunk-0",),
        )
    )
    assert result.permitted is False
    assert result.decision == ResumeCompatibilityDecision.UNAUTHORIZED_CHUNK


def test_evaluate_resume_compatibility_rejects_unaccepted_manifest() -> None:
    result = evaluate_resume_compatibility(
        **_base_kwargs(manifest_validation_status="pending"),
    )
    assert result.permitted is False
    assert result.decision == ResumeCompatibilityDecision.CHECKPOINT_NOT_ACCEPTED


def test_require_compatible_raises_checkpoint_incompatible_for_model_space() -> None:
    result = evaluate_resume_compatibility(
        **_base_kwargs(grant_runtime_version="other-runtime"),
    )
    with pytest.raises(WorkerServiceError) as exc:
        CheckpointResumeService.require_compatible(result)
    assert exc.value.code == "CHECKPOINT_INCOMPATIBLE"
