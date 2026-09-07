"""Artifact upload, retention and privacy cleanup rules (Architecture v2 §54, §55, §61, A21/T21)."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from enum import StrEnum
from pathlib import Path
from typing import Any

import yaml

from edgemint.files.input_decode_bounds import load_input_decode_privacy_policy


class UploadArtifactState(StrEnum):
    PARTIAL = "partial"
    COMPLETE = "complete"


class CleanupFailureReason(StrEnum):
    CLEANUP_PERMITTED = "CLEANUP_PERMITTED"
    RETENTION_ACTIVE = "RETENTION_ACTIVE"
    LEGAL_HOLD = "LEGAL_HOLD"
    CHECKPOINT_REFERENCE_ACTIVE = "CHECKPOINT_REFERENCE_ACTIVE"


@dataclass(frozen=True, slots=True)
class UploadAcceptanceDecision:
    accepted: bool
    reason_code: str
    detail: str | None = None


@dataclass(frozen=True, slots=True)
class RetentionCleanupDecision:
    permitted: bool
    reason_code: CleanupFailureReason
    detail: str | None = None


def evaluate_upload_acceptance(
    *,
    upload_state: UploadArtifactState,
    sha256_verified: bool,
    size_matches: bool,
) -> UploadAcceptanceDecision:
    if upload_state != UploadArtifactState.COMPLETE:
        return UploadAcceptanceDecision(
            accepted=False,
            reason_code="UPLOAD_INCOMPLETE",
            detail="partial upload cannot become task input artifact",
        )
    if not sha256_verified:
        return UploadAcceptanceDecision(
            accepted=False,
            reason_code="FILE_DIGEST_MISMATCH",
            detail="digest verification required before acceptance",
        )
    if not size_matches:
        return UploadAcceptanceDecision(
            accepted=False,
            reason_code="UPLOAD_INCOMPLETE",
            detail="uploaded size mismatch",
        )
    return UploadAcceptanceDecision(accepted=True, reason_code="ACCEPTED")


def evaluate_retention_cleanup(
    *,
    created_at: datetime,
    now: datetime,
    retention_minutes: int,
    has_active_references: bool,
    legal_hold: bool = False,
    policy: dict[str, Any] | None = None,
) -> RetentionCleanupDecision:
    loaded = policy or load_input_decode_privacy_policy()
    retention_cfg = loaded.get("retention") or {}
    if legal_hold and retention_cfg.get("legalHoldBlocksCleanup", True):
        return RetentionCleanupDecision(
            permitted=False,
            reason_code=CleanupFailureReason.LEGAL_HOLD,
            detail="legal hold blocks cleanup",
        )
    if has_active_references and retention_cfg.get("checkpointRetainUntilServerRevoke", True):
        return RetentionCleanupDecision(
            permitted=False,
            reason_code=CleanupFailureReason.CHECKPOINT_REFERENCE_ACTIVE,
            detail="active checkpoint/resume reference blocks cleanup",
        )

    created = created_at if created_at.tzinfo else created_at.replace(tzinfo=UTC)
    current = now if now.tzinfo else now.replace(tzinfo=UTC)
    worker_minutes = int(retention_cfg.get("workerTemporaryMinutes", retention_minutes))
    if current - created < timedelta(minutes=max(1, worker_minutes)):
        return RetentionCleanupDecision(
            permitted=False,
            reason_code=CleanupFailureReason.RETENTION_ACTIVE,
            detail=f"retention window {worker_minutes} minutes not elapsed",
        )
    return RetentionCleanupDecision(
        permitted=True,
        reason_code=CleanupFailureReason.CLEANUP_PERMITTED,
    )


def assignment_scoped_temp_path(*, workspace_id: str, assignment_id: str, suffix: str) -> str:
    safe_suffix = suffix.replace("/", "_").replace("\\", "_")[:120]
    return f"workspaces/{workspace_id}/tmp/{assignment_id}/{safe_suffix}"


def cross_task_isolation_violated(
    *,
    prior_assignment_id: str | None,
    next_assignment_id: str,
    shared_buffer_owner: str | None,
) -> bool:
    if prior_assignment_id is None or shared_buffer_owner is None:
        return False
    return prior_assignment_id != next_assignment_id and shared_buffer_owner == prior_assignment_id
