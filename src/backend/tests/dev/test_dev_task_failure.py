from __future__ import annotations

from unittest.mock import patch

import pytest
from edgemint.dev import fixtures, worker_assignments, worker_task_inputs
from edgemint.dev.dev_worker_api import DevTaskFailureRequest, report_worker_task_failure


def _reset_assignments(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("EDGEMINT_DEV_PIN_DEVICE_ID", raising=False)
    worker_assignments._pending.clear()
    worker_assignments._completed.clear()
    worker_assignments._delivered_devices.clear()
    worker_assignments._in_flight_devices.clear()
    worker_assignments._failed_devices.clear()
    worker_assignments._cancelled_ids.clear()
    worker_assignments._exclusive_device_public_id = None


def test_single_worker_failure_is_terminal(monkeypatch: pytest.MonkeyPatch) -> None:
    _reset_assignments(monkeypatch)
    worker_assignments.enqueue_dev_assignment(task_id="tsk_one_worker", task_type="text.summarize")
    claimed = worker_assignments.claim_next_assignment(device_public_id="worker_a")
    assert claimed is not None

    terminal = worker_assignments.record_worker_failure(
        task_id="tsk_one_worker",
        device_id="worker_a",
        error_code="RUNTIME_CRASH",
    )

    assert terminal is True


def test_failure_waits_until_every_recipient_has_failed(monkeypatch: pytest.MonkeyPatch) -> None:
    _reset_assignments(monkeypatch)
    worker_assignments.enqueue_dev_assignment(task_id="tsk_two_workers", task_type="text.summarize")
    first = worker_assignments.claim_next_assignment(device_public_id="worker_a")
    worker_assignments.enqueue_dev_assignment(task_id="tsk_two_workers", task_type="text.summarize")
    second = worker_assignments.claim_next_assignment(device_public_id="worker_b")
    assert first is not None
    assert second is not None

    assert (
        worker_assignments.record_worker_failure(
            task_id="tsk_two_workers",
            device_id="worker_a",
            error_code="RUNTIME_CRASH",
        )
        is False
    )
    assert (
        worker_assignments.record_worker_failure(
            task_id="tsk_two_workers",
            device_id="worker_b",
            error_code="MODEL_EXECUTION_FAILED",
        )
        is True
    )


def test_reject_dev_task_output_marks_portal_task_failed() -> None:
    with patch("edgemint.dev.assignment_bridge.enqueue_assignment_for_worker", return_value={}):
        task = fixtures.create_dev_task(
            fixtures.DEV_WORKSPACE_PRIMARY,
            task_type="text.summarize",
            input_text="Source body.",
        )
    assert task["lifecycleStatus"] == "queued"

    assert fixtures.reject_dev_task_output(
        task["id"],
        reason_code="RUNTIME_CRASH",
        reason_detail="RUNTIME_CRASH",
    )
    stored = fixtures.dev_task_by_id(task["id"])
    assert stored is not None
    assert stored["lifecycleStatus"] == "failed"
    assert stored["executionStatus"] == "failed"
    assert stored["failureReasonCode"] == "RUNTIME_CRASH"
    assert stored["failureReason"] == "RUNTIME_CRASH"

    fixtures.update_dev_task_execution(
        task["id"],
        lifecycle_status="succeeded",
        execution_status="completed",
    )
    assert (
        fixtures.reject_dev_task_output(
            task["id"],
            reason_code="RUNTIME_CRASH",
            reason_detail="RUNTIME_CRASH",
        )
        is False
    )
    assert fixtures.dev_task_by_id(task["id"])["lifecycleStatus"] == "succeeded"


def test_failed_task_is_not_synced_back_to_workers() -> None:
    with patch("edgemint.dev.assignment_bridge.enqueue_assignment_for_worker", return_value={}):
        task = fixtures.create_dev_task(
            fixtures.DEV_WORKSPACE_PRIMARY,
            task_type="text.summarize",
            input_text="Source body.",
        )
    fixtures.reject_dev_task_output(
        task["id"],
        reason_code="RUNTIME_CRASH",
        reason_detail="RUNTIME_CRASH",
    )
    stored = fixtures.dev_task_by_id(task["id"])
    assert stored is not None

    with (
        patch(
            "edgemint.dev.assignment_bridge.fetch_pending_assignments_from_worker",
            return_value=[],
        ),
        patch("edgemint.dev.assignment_bridge.enqueue_assignment_for_worker") as enqueue,
    ):
        fixtures._sync_pending_tasks_to_worker_queue([stored])

    enqueue.assert_not_called()


@pytest.mark.asyncio
async def test_failure_endpoint_updates_portal_task() -> None:
    with patch("edgemint.dev.assignment_bridge.enqueue_assignment_for_worker", return_value={}):
        task = fixtures.create_dev_task(
            fixtures.DEV_WORKSPACE_PRIMARY,
            task_type="text.summarize",
            input_text="Source body.",
        )

    await report_worker_task_failure(
        task["id"],
        DevTaskFailureRequest(errorCode="MODEL_EXECUTION_FAILED", detail="MODEL_EXECUTION_FAILED"),
    )

    stored = fixtures.dev_task_by_id(task["id"])
    assert stored is not None
    assert stored["lifecycleStatus"] == "failed"
    assert stored["executionStatus"] == "failed"


def test_cancel_stays_visible_after_the_worker_has_claimed(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _reset_assignments(monkeypatch)
    worker_assignments.enqueue_dev_assignment(task_id="tsk_cancel_live", task_type="text.direct")
    claimed = worker_assignments.claim_next_assignment(device_public_id="worker_a")
    assert claimed is not None
    assert worker_assignments.is_assignment_cancelled("tsk_cancel_live") is False

    worker_assignments.cancel_dev_assignment("tsk_cancel_live")

    assert worker_assignments.is_assignment_cancelled("tsk_cancel_live") is True
    worker_assignments.enqueue_dev_assignment(task_id="tsk_cancel_live", task_type="text.direct")
    assert worker_assignments.claim_next_assignment(device_public_id="worker_a") is None


def test_late_output_does_not_resurrect_a_cancelled_task() -> None:
    with patch("edgemint.dev.assignment_bridge.enqueue_assignment_for_worker", return_value={}):
        task = fixtures.create_dev_task(
            fixtures.DEV_WORKSPACE_PRIMARY,
            task_type="text.direct",
            input_text="Write a long answer.",
        )
    fixtures.update_dev_task_execution(
        task["id"],
        lifecycle_status="cancelled",
        execution_status="cancelled",
    )

    worker_task_inputs.record_output(task_id=task["id"], result_text="finished after cancel")

    stored = fixtures.dev_task_by_id(task["id"])
    assert stored is not None
    assert stored["lifecycleStatus"] == "cancelled"
    assert stored["executionStatus"] == "cancelled"
    assert stored.get("resultText") != "finished after cancel"
