from __future__ import annotations

from collections import defaultdict
from typing import Any


def workspace_fair_queue_metrics(attempts: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Section 9 deficit metrics for starvation monitoring."""
    buckets: dict[str, dict[str, int | float]] = defaultdict(
        lambda: {
            "deficitUnits": 0,
            "waitingTaskCount": 0,
            "maxWaitingSeconds": 0.0,
            "starvedTaskCount": 0,
        }
    )
    for attempt in attempts:
        workspace_id = str(attempt["workspaceId"])
        bucket = buckets[workspace_id]
        bucket["deficitUnits"] = int(bucket["deficitUnits"]) + int(attempt.get("deficitUnits", 0))
        bucket["waitingTaskCount"] = int(bucket["waitingTaskCount"]) + 1
        waiting = float(attempt.get("waitingSeconds", 0))
        bucket["maxWaitingSeconds"] = max(float(bucket["maxWaitingSeconds"]), waiting)
        if waiting >= float(attempt.get("starvationLimitSeconds", 300)):
            bucket["starvedTaskCount"] = int(bucket["starvedTaskCount"]) + 1

    return [
        {
            "workspaceId": workspace_id,
            "deficitUnits": int(values["deficitUnits"]),
            "waitingTaskCount": int(values["waitingTaskCount"]),
            "maxWaitingSeconds": float(values["maxWaitingSeconds"]),
            "starvedTaskCount": int(values["starvedTaskCount"]),
        }
        for workspace_id, values in sorted(buckets.items())
    ]
