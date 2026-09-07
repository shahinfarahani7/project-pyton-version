"""Operating signals for queue fairness and backpressure blockers (Architecture v2 §73, A19)."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from edgemint.routing.admission_backpressure import (
    BackpressureDecision,
    PipelinePressureSnapshot,
)
from edgemint.routing.fair_queue_metrics import workspace_fair_queue_metrics
from edgemint.routing.workspace_drr import WorkspaceDrrState


@dataclass(frozen=True, slots=True)
class OperatingSignalSnapshot:
    queue_age_seconds: float
    blocked_reason: str
    workspace_deficit_units: int
    starved_task_count: int
    validation_backlog: int
    upload_in_flight: int
    outbox_pending: int

    def to_dict(self) -> dict[str, Any]:
        return {
            "queueAgeSeconds": self.queue_age_seconds,
            "blockedReason": self.blocked_reason,
            "workspaceDeficitUnits": self.workspace_deficit_units,
            "starvedTaskCount": self.starved_task_count,
            "validationBacklog": self.validation_backlog,
            "uploadInFlight": self.upload_in_flight,
            "outboxPending": self.outbox_pending,
        }


def collect_operating_signals(
    *,
    attempts: list[dict[str, Any]],
    drr_state: WorkspaceDrrState,
    pipeline: PipelinePressureSnapshot,
    admission: BackpressureDecision | None = None,
) -> list[dict[str, Any]]:
    """Emit per-workspace operating signals without sensitive payloads."""
    metrics = workspace_fair_queue_metrics(attempts)
    blocked_reason = admission.reason_code.value if admission and not admission.permitted else "NONE"
    signals: list[dict[str, Any]] = []

    for row in metrics:
        workspace_id = str(row["workspaceId"])
        snapshot = OperatingSignalSnapshot(
            queue_age_seconds=float(row["maxWaitingSeconds"]),
            blocked_reason=blocked_reason,
            workspace_deficit_units=drr_state.deficit(workspace_id),
            starved_task_count=int(row["starvedTaskCount"]),
            validation_backlog=pipeline.validation_backlog,
            upload_in_flight=pipeline.upload_in_flight,
            outbox_pending=pipeline.outbox_pending,
        )
        signals.append(
            {
                "workspaceId": workspace_id,
                **snapshot.to_dict(),
                "waitingTaskCount": int(row["waitingTaskCount"]),
            }
        )
    return signals


def reveal_primary_blocker(signals: list[dict[str, Any]]) -> str | None:
    """Return the dominant blocked reason for alert routing."""
    if not signals:
        return None
    starved = sum(int(item.get("starvedTaskCount", 0)) for item in signals)
    if starved > 0:
        return "STARVATION_RISK"
    blocked = next((item.get("blockedReason") for item in signals if item.get("blockedReason") not in {None, "NONE"}), None)
    if blocked:
        return str(blocked)
    max_age = max(float(item.get("queueAgeSeconds", 0)) for item in signals)
    if max_age >= 600:
        return "QUEUE_AGE_SLO_BREACH"
    return None
