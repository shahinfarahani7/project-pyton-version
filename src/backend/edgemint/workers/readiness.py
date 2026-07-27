from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime

from edgemint.building_blocks.settings import Settings, get_settings
from edgemint.workers.errors import worker_error
from edgemint.workers.lifecycle import PAID_WORK_READY_STATUSES, TERMINAL_STATUSES


@dataclass(frozen=True, slots=True)
class WorkerReadinessSnapshot:
    worker_status: str
    device_status: str
    attestation_status: str
    attestation_expires_at: datetime
    consent_policy_version: str | None
    consent_withdrawn: bool
    preferences_availability: str
    has_benchmark: bool


def assess_paid_work_eligibility(
    snapshot: WorkerReadinessSnapshot,
    *,
    settings: Settings | None = None,
    now: datetime | None = None,
) -> None:
    active = settings or get_settings()
    current = now or datetime.now(UTC)
    if snapshot.worker_status in TERMINAL_STATUSES | {"quarantined", "suspended"}:
        raise worker_error("WORKER_QUARANTINED")
    if snapshot.worker_status not in PAID_WORK_READY_STATUSES:
        raise worker_error("WORKER_NOT_READY", detail=f"status={snapshot.worker_status}")
    if snapshot.device_status not in {"active", "ready"}:
        raise worker_error("WORKER_NOT_READY", detail=f"device_status={snapshot.device_status}")
    if snapshot.attestation_status != "verified":
        raise worker_error("ATTESTATION_INVALID", detail="attestation not verified")
    if snapshot.attestation_expires_at <= current:
        raise worker_error("ATTESTATION_INVALID", detail="attestation expired")
    if snapshot.consent_withdrawn:
        raise worker_error("CONSENT_MISMATCH", detail="consent withdrawn")
    if snapshot.consent_policy_version != active.worker_consent_policy_version:
        raise worker_error("CONSENT_MISMATCH")
    if snapshot.preferences_availability != "available":
        raise worker_error("WORKER_NOT_READY", detail="worker unavailable")
    if not snapshot.has_benchmark:
        raise worker_error("WORKER_NOT_READY", detail="benchmark required")


def derive_device_tier(results: list[dict[str, float | str]]) -> str:
    score = 0.0
    for item in results:
        metric = str(item.get("metric", ""))
        value = float(item.get("value", 0))
        if metric in {"tokens_per_second", "inference_ops_per_second"}:
            score = max(score, value)
    if score >= 120:
        return "A"
    if score >= 60:
        return "B"
    if score >= 20:
        return "C"
    return "D"
