from __future__ import annotations

from datetime import UTC, datetime, timedelta
from unittest.mock import MagicMock, patch

from edgemint.dev import worker_assignments
from edgemint.dev.assignment_bridge import (
    clear_exclusive_device_pin_on_worker_registry,
    enqueue_assignment_for_worker,
)


def test_clear_exclusive_pin_posts_to_worker_registry() -> None:
    with patch("edgemint.dev.assignment_bridge.httpx.Client") as client_cls:
        client = MagicMock()
        client.__enter__.return_value = client
        response = MagicMock()
        response.raise_for_status.return_value = None
        client.post.return_value = response
        client_cls.return_value = client

        clear_exclusive_device_pin_on_worker_registry()

        client.post.assert_called_once()
        assert client.post.call_args.args[0].endswith(
            "/internal/dev/clear-exclusive-device-pin"
        )


def test_enqueue_assignment_falls_back_to_local_queue_on_http_error() -> None:
    with patch("edgemint.dev.assignment_bridge.httpx.Client") as client_cls:
        client = MagicMock()
        client.__enter__.return_value = client
        client.post.side_effect = RuntimeError("connection refused")
        client_cls.return_value = client

        with patch("edgemint.dev.worker_assignments.enqueue_dev_assignment") as enqueue:
            enqueue_assignment_for_worker(task_id="tsk_dev_abc", task_type="text.generate")
            enqueue.assert_called_once_with(task_id="tsk_dev_abc", task_type="text.generate")


def test_one_task_goes_to_a_random_online_phone_and_does_not_pin(monkeypatch) -> None:
    worker_assignments._pending.clear()
    worker_assignments._completed.clear()
    worker_assignments._exclusive_device_public_id = None
    worker_assignments.clear_online_devices()
    phones = ["phone_a", "phone_b", "phone_c", "phone_d"]
    choices = iter(["phone_c", "phone_a"])
    monkeypatch.setattr(
        worker_assignments,
        "choose_online_device",
        lambda device_ids, requesting: next(choices),
    )

    for phone in phones:
        assert worker_assignments.claim_next_assignment(device_public_id=phone) is None

    worker_assignments.enqueue_dev_assignment(
        task_id="tsk_dev_random",
        task_type="text.summarize",
    )
    assert (
        worker_assignments.claim_next_assignment(
            device_public_id="phone_a",
            claim_exclusive=True,
        )
        is None
    )
    chosen = worker_assignments.claim_next_assignment(device_public_id="phone_c")
    assert chosen is not None
    assert chosen["taskId"] == "tsk_dev_random"
    assert worker_assignments.preferred_device_public_id() is None

    worker_assignments.enqueue_dev_assignment(
        task_id="tsk_dev_second",
        task_type="text.summarize",
    )
    assert worker_assignments.claim_next_assignment(device_public_id="phone_c") is None
    second = worker_assignments.claim_next_assignment(device_public_id="phone_a")
    assert second is not None
    assert second["taskId"] == "tsk_dev_second"


def test_sync_clears_runtime_exclusive_pin_when_unpinned(monkeypatch) -> None:
    worker_assignments._pending.clear()
    worker_assignments._completed.clear()
    worker_assignments._exclusive_device_public_id = "dev_old_emulator"
    monkeypatch.delenv("EDGEMINT_DEV_PIN_DEVICE_ID", raising=False)

    worker_assignments.clear_runtime_exclusive_device_pin()

    assert worker_assignments.preferred_device_public_id() is None


def test_dev_assignment_deadlines_begin_when_delivered(
    monkeypatch,
) -> None:
    worker_assignments._pending.clear()
    worker_assignments._completed.clear()
    worker_assignments.clear_online_devices()
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
