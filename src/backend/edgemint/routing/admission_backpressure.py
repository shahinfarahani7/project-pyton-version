"""Queue admission and pipeline backpressure (Architecture v2 §31, §40, §73, A19/T19)."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path
from typing import Any

from edgemint.routing.workspace_drr import load_admission_backpressure_policy


class BackpressureReason(StrEnum):
    ADMITTED = "ADMITTED"
    ADMISSION_LIMIT_EXCEEDED = "ADMISSION_LIMIT_EXCEEDED"
    QUEUE_BACKPRESSURE = "QUEUE_BACKPRESSURE"
    CAPACITY_SATURATED = "CAPACITY_SATURATED"
    NO_ELIGIBLE_WORKER = "NO_ELIGIBLE_WORKER"
    OUTBOX_BACKPRESSURE = "OUTBOX_BACKPRESSURE"
    UPLOAD_BACKPRESSURE = "UPLOAD_BACKPRESSURE"
    VALIDATION_BACKPRESSURE = "VALIDATION_BACKPRESSURE"


@dataclass(frozen=True, slots=True)
class BackpressureDecision:
    permitted: bool
    reason_code: BackpressureReason
    detail: str | None = None
    bounded_wait_seconds: int | None = None


@dataclass(frozen=True, slots=True)
class PipelinePressureSnapshot:
    outbox_pending: int = 0
    upload_in_flight: int = 0
    validation_backlog: int = 0


def evaluate_queue_admission(
    *,
    workspace_id: str,
    queued_count: int,
    active_count: int,
    input_cost_units: int,
    policy: dict[str, Any] | None = None,
) -> BackpressureDecision:
    loaded = policy or load_admission_backpressure_policy()
    caps = loaded.get("workspaceCaps") or {}
    max_queued = int(caps.get("maxQueuedTasksPerWorkspace", 0))
    max_active = int(caps.get("maxActiveTasksPerWorkspace", 0))
    max_input_cost = int(caps.get("maxAcceptedInputCostUnits", 0))
    max_wait = int((loaded.get("boundedRejection") or {}).get("maxAdmissionWaitSeconds", 300))

    if max_queued <= 0 or max_active <= 0 or max_input_cost <= 0:
        return BackpressureDecision(
            permitted=False,
            reason_code=BackpressureReason.QUEUE_BACKPRESSURE,
            detail="missing queue capacity policy blocks admission",
            bounded_wait_seconds=max_wait,
        )

    if queued_count >= max_queued:
        return BackpressureDecision(
            permitted=False,
            reason_code=BackpressureReason.ADMISSION_LIMIT_EXCEEDED,
            detail=f"workspace {workspace_id} queued cap reached ({queued_count}/{max_queued})",
            bounded_wait_seconds=max_wait,
        )

    if active_count >= max_active:
        return BackpressureDecision(
            permitted=False,
            reason_code=BackpressureReason.CAPACITY_SATURATED,
            detail=f"workspace {workspace_id} active cap reached ({active_count}/{max_active})",
            bounded_wait_seconds=max_wait,
        )

    if input_cost_units > max_input_cost:
        return BackpressureDecision(
            permitted=False,
            reason_code=BackpressureReason.ADMISSION_LIMIT_EXCEEDED,
            detail=f"input cost {input_cost_units} exceeds cap {max_input_cost}",
            bounded_wait_seconds=max_wait,
        )

    return BackpressureDecision(
        permitted=True,
        reason_code=BackpressureReason.ADMITTED,
    )


def evaluate_pipeline_backpressure(
    snapshot: PipelinePressureSnapshot,
    *,
    policy: dict[str, Any] | None = None,
) -> BackpressureDecision:
    loaded = policy or load_admission_backpressure_policy()
    pipeline = loaded.get("pipelineBackpressure") or {}
    max_wait = int((loaded.get("boundedRejection") or {}).get("maxAdmissionWaitSeconds", 300))

    outbox_cfg = pipeline.get("outbox") or {}
    upload_cfg = pipeline.get("uploads") or {}
    validation_cfg = pipeline.get("validation") or {}

    outbox_max = int(outbox_cfg.get("maxPendingEvents", 0))
    upload_max = int(upload_cfg.get("maxInFlight", 0))
    validation_max = int(validation_cfg.get("maxBacklog", 0))

    if outbox_max <= 0 or upload_max <= 0 or validation_max <= 0:
        return BackpressureDecision(
            permitted=False,
            reason_code=BackpressureReason.QUEUE_BACKPRESSURE,
            detail="missing pipeline capacity policy blocks admission",
            bounded_wait_seconds=max_wait,
        )

    if snapshot.outbox_pending >= outbox_max:
        return BackpressureDecision(
            permitted=False,
            reason_code=BackpressureReason.OUTBOX_BACKPRESSURE,
            detail=f"outbox pending {snapshot.outbox_pending}/{outbox_max}",
            bounded_wait_seconds=max_wait,
        )

    if snapshot.upload_in_flight >= upload_max:
        return BackpressureDecision(
            permitted=False,
            reason_code=BackpressureReason.UPLOAD_BACKPRESSURE,
            detail=f"upload in-flight {snapshot.upload_in_flight}/{upload_max}",
            bounded_wait_seconds=max_wait,
        )

    if snapshot.validation_backlog >= validation_max:
        return BackpressureDecision(
            permitted=False,
            reason_code=BackpressureReason.VALIDATION_BACKPRESSURE,
            detail=f"validation backlog {snapshot.validation_backlog}/{validation_max}",
            bounded_wait_seconds=max_wait,
        )

    return BackpressureDecision(
        permitted=True,
        reason_code=BackpressureReason.ADMITTED,
    )


def evaluate_admission_backpressure(
    *,
    workspace_id: str,
    queued_count: int,
    active_count: int,
    input_cost_units: int,
    pipeline: PipelinePressureSnapshot,
    policy: dict[str, Any] | None = None,
) -> BackpressureDecision:
    """Combined queue + pipeline admission gate with distinct blocked reasons."""
    queue = evaluate_queue_admission(
        workspace_id=workspace_id,
        queued_count=queued_count,
        active_count=active_count,
        input_cost_units=input_cost_units,
        policy=policy,
    )
    if not queue.permitted:
        return queue
    pipeline_decision = evaluate_pipeline_backpressure(pipeline, policy=policy)
    if not pipeline_decision.permitted:
        return pipeline_decision
    return queue
