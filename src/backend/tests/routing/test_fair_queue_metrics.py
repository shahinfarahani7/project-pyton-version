from __future__ import annotations

from edgemint.routing.fair_queue_metrics import workspace_fair_queue_metrics
from edgemint.routing.service import RouterService


def test_workspace_fair_queue_metrics_aggregate_deficits() -> None:
    attempts = [
        {"workspaceId": "ws_a", "deficitUnits": 2, "waitingSeconds": 10, "starvationLimitSeconds": 300},
        {"workspaceId": "ws_a", "deficitUnits": 1, "waitingSeconds": 400, "starvationLimitSeconds": 300},
        {"workspaceId": "ws_b", "deficitUnits": 5, "waitingSeconds": 30, "starvationLimitSeconds": 300},
    ]
    metrics = workspace_fair_queue_metrics(attempts)
    assert metrics == [
        {
            "workspaceId": "ws_a",
            "deficitUnits": 3,
            "waitingTaskCount": 2,
            "maxWaitingSeconds": 400.0,
            "starvedTaskCount": 1,
        },
        {
            "workspaceId": "ws_b",
            "deficitUnits": 5,
            "waitingTaskCount": 1,
            "maxWaitingSeconds": 30.0,
            "starvedTaskCount": 0,
        },
    ]


def test_router_service_exposes_workspace_metrics() -> None:
    router = RouterService()
    metrics = router.workspace_fair_queue_metrics(
        [{"workspaceId": "ws_x", "deficitUnits": 4, "waitingSeconds": 5, "starvationLimitSeconds": 300}]
    )
    assert metrics[0]["workspaceId"] == "ws_x"
    assert metrics[0]["deficitUnits"] == 4
