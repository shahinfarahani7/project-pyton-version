from __future__ import annotations

from datetime import UTC, datetime

from edgemint.routing.fair_queue import rank_task_attempts
from edgemint.routing.service import RouterService


def _attempt(**overrides: object) -> dict[str, object]:
    base: dict[str, object] = {
        "attemptId": "att_base",
        "workspaceId": "ws_1",
        "priorityBps": 2000,
        "submittedAt": datetime(2026, 9, 1, 10, 0, tzinfo=UTC),
        "deadlineAt": None,
        "taskId": "tsk_base",
        "deficitUnits": 0,
        "waitingSeconds": 0,
    }
    base.update(overrides)
    return base


def test_deficit_round_robin_orders_by_higher_deficit_first() -> None:
    ordered = rank_task_attempts(
        [
            _attempt(attemptId="att_high_deficit", deficitUnits=5, taskId="tsk_a"),
            _attempt(attemptId="att_low_deficit", deficitUnits=1, taskId="tsk_b"),
        ]
    )
    assert ordered[0] == "att_high_deficit"


def test_priority_breaks_deficit_ties() -> None:
    ordered = rank_task_attempts(
        [
            _attempt(attemptId="att_low_pri", priorityBps=1000, deficitUnits=1, taskId="tsk_a"),
            _attempt(attemptId="att_high_pri", priorityBps=3000, deficitUnits=1, taskId="tsk_b"),
        ]
    )
    assert ordered[0] == "att_high_pri"


def test_deadline_precedes_submission_time() -> None:
    ordered = rank_task_attempts(
        [
            _attempt(
                attemptId="att_late_deadline",
                deadlineAt=datetime(2026, 9, 2, 10, 0, tzinfo=UTC),
                submittedAt=datetime(2026, 9, 1, 9, 0, tzinfo=UTC),
                taskId="tsk_a",
            ),
            _attempt(
                attemptId="att_early_deadline",
                deadlineAt=datetime(2026, 9, 1, 12, 0, tzinfo=UTC),
                submittedAt=datetime(2026, 9, 1, 10, 0, tzinfo=UTC),
                taskId="tsk_b",
            ),
        ]
    )
    assert ordered[0] == "att_early_deadline"


def test_starvation_override_promotes_long_waiting_task() -> None:
    service = RouterService()
    ordered = service.rank_task_attempts(
        [
            _attempt(attemptId="att_fresh", deficitUnits=5, waitingSeconds=10, taskId="tsk_a"),
            _attempt(attemptId="att_starved", deficitUnits=1, waitingSeconds=400, taskId="tsk_b"),
        ]
    )
    assert ordered[0] == "att_starved"
