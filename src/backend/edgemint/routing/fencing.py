from __future__ import annotations

import hashlib
import hmac
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from edgemint.routing.errors import router_error


def compute_tie_breaker(*, task_id: str, worker_id: str, router_epoch: int, secret: str) -> str:
    payload = f"{task_id}:{worker_id}:{router_epoch}".encode()
    return hmac.new(secret.encode("utf-8"), payload, hashlib.sha256).hexdigest()


def assert_monotonic_fence(*, presented: int, current: int) -> None:
    if presented != current:
        raise router_error("ASSIGNMENT_STALE_FENCE", detail=f"presented={presented}, current={current}")


def assert_renewal_sequence(*, presented: int, last_renewal: int) -> None:
    if presented <= last_renewal:
        raise router_error("LEASE_RENEWAL_REJECTED", detail="sequence not monotonic")


@dataclass(frozen=True, slots=True)
class QueueAttempt:
    attempt_id: str
    workspace_id: str
    priority_bps: int
    submitted_at: datetime
    deadline_at: datetime | None
    task_id: str
    deficit_units: int = 0
    waiting_seconds: float = 0.0


def rank_queue_attempts(
    attempts: list[QueueAttempt],
    *,
    starvation_limit_seconds: int = 300,
) -> list[QueueAttempt]:
    def sort_key(item: QueueAttempt) -> tuple[int, int, int, float, datetime, str, str]:
        stale_rank = 0 if item.waiting_seconds >= starvation_limit_seconds else 1
        deadline_key = item.deadline_at.timestamp() if item.deadline_at else float("inf")
        return (
            stale_rank,
            -item.deficit_units,
            -item.priority_bps,
            deadline_key,
            item.submitted_at.timestamp(),
            item.task_id,
            item.attempt_id,
        )

    return sorted(attempts, key=sort_key)


def tier_capacity(device_tier: str) -> int:
    return 2 if device_tier == "T4" else 1


def assert_capacity_available(*, active_leases: int, device_tier: str) -> None:
    if active_leases >= tier_capacity(device_tier):
        raise router_error("WORKER_CAPACITY_EXHAUSTED")


def assert_reassignment_budget(*, assignment_count: int, max_reassignments: int) -> None:
    if assignment_count > max_reassignments:
        raise router_error("NO_CAPACITY", detail="reassignment budget exhausted")


def routing_decision_explanation(
    *,
    attempt_id: str,
    worker_id: str,
    score: int,
    eligible: bool,
    reasons: list[str],
) -> dict[str, Any]:
    return {
        "attemptId": attempt_id,
        "workerId": worker_id,
        "eligible": eligible,
        "score": score,
        "ineligibilityReasons": reasons,
        "assignmentMode": "server_auto_lease",
        "workerConfirmationRequired": False,
        "deliveryAckMeaning": "transport_receipt_only",
    }
