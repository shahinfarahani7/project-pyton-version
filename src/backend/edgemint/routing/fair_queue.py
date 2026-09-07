from __future__ import annotations

from datetime import datetime
from typing import Any

from edgemint.routing.fencing import QueueAttempt, rank_queue_attempts
from edgemint.routing.policy import RoutingPolicy


def rank_task_attempts(
    attempts: list[dict[str, Any]],
    *,
    policy: RoutingPolicy | None = None,
) -> list[str]:
    """Section 9 queue ordering: deficit RR → priority → deadline → age → task ID."""
    active = policy or RoutingPolicy.load()
    queue_policy = active.spec["queueSelection"]
    starvation_limit = int(queue_policy.get("starvationLimitSeconds", 300))
    parsed = [
        QueueAttempt(
            attempt_id=str(item["attemptId"]),
            workspace_id=str(item["workspaceId"]),
            priority_bps=int(item["priorityBps"]),
            submitted_at=item["submittedAt"]
            if isinstance(item["submittedAt"], datetime)
            else datetime.fromisoformat(str(item["submittedAt"]).replace("Z", "+00:00")),
            deadline_at=(
                None
                if item.get("deadlineAt") is None
                else (
                    item["deadlineAt"]
                    if isinstance(item["deadlineAt"], datetime)
                    else datetime.fromisoformat(str(item["deadlineAt"]).replace("Z", "+00:00"))
                )
            ),
            task_id=str(item["taskId"]),
            deficit_units=int(item.get("deficitUnits", 0)),
            waiting_seconds=float(item.get("waitingSeconds", 0)),
        )
        for item in attempts
    ]
    return [item.attempt_id for item in rank_queue_attempts(parsed, starvation_limit_seconds=starvation_limit)]
