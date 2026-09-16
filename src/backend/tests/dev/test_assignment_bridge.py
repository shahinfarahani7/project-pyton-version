from __future__ import annotations

from datetime import UTC, datetime, timedelta
from unittest.mock import MagicMock, patch

from edgemint.dev import worker_assignments
from edgemint.dev.assignment_bridge import enqueue_assignment_for_worker


def test_enqueue_assignment_falls_back_to_local_queue_on_http_error() -> None:
    with patch("edgemint.dev.assignment_bridge.httpx.Client") as client_cls:
        client = MagicMock()
        client.__enter__.return_value = client
        client.post.side_effect = RuntimeError("connection refused")
        client_cls.return_value = client

        with patch("edgemint.dev.worker_assignments.enqueue_dev_assignment") as enqueue:
            enqueue_assignment_for_worker(task_id="tsk_dev_abc", task_type="text.generate")
            enqueue.assert_called_once_with(task_id="tsk_dev_abc", task_type="text.generate")


def test_dev_assignment_deadlines_begin_when_delivered(
    monkeypatch,
) -> None:
    worker_assignments._pending.clear()
    worker_assignments._completed.clear()
    queued_at = datetime(2026, 1, 1, tzinfo=UTC)
    delivered_at = queued_at + timedelta(hours=2)

    monkeypatch.setattr(worker_assignments, "_now", lambda: queued_at)
    worker_assignments.enqueue_dev_assignment(
        task_id="tsk_delivery_deadline",
        task_type="text.summarize",
    )

    monkeypatch.setattr(worker_assignments, "_now", lambda: delivered_at)
    assignment = worker_assignments.pop_next_assignment()

    assert assignment is not None
    assert datetime.fromisoformat(assignment["startDeadlineAt"]) == (
        delivered_at + timedelta(minutes=5)
    )
    assert datetime.fromisoformat(assignment["leaseExpiresAt"]) == (
        delivered_at + timedelta(minutes=30)
    )
