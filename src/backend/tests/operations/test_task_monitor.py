from __future__ import annotations

from collections.abc import Iterator
from uuid import uuid4

import pytest
from edgemint.dev import fixtures, worker_assignments
from edgemint.operations.task_monitor import build_task_monitor, device_ids_in, device_record_from_row


@pytest.fixture(autouse=True)
def _clean_assignment_state() -> Iterator[None]:
    def reset() -> None:
        worker_assignments._pending.clear()
        worker_assignments._completed.clear()
        worker_assignments._delivered_devices.clear()
        worker_assignments._in_flight_devices.clear()
        worker_assignments._failed_devices.clear()
        worker_assignments._delivered_at.clear()
        worker_assignments._cancelled_ids.clear()

    reset()
    yield
    reset()


def test_delivery_ledger_tracks_device_and_outcome() -> None:
    worker_assignments.note_task_delivery("tsk_run", "dev_A")
    worker_assignments.note_task_delivery("tsk_fail", "dev_B")
    worker_assignments.record_worker_failure(task_id="tsk_fail", device_id="dev_B", error_code="OOM")
    worker_assignments.note_task_delivery("tsk_done", "dev_A")
    worker_assignments._in_flight_devices["tsk_done"].discard("dev_A")
    worker_assignments.mark_completed("tsk_done")
    worker_assignments.note_task_delivery("tsk_cancel", "dev_C")
    worker_assignments.cancel_dev_assignment("tsk_cancel")

    ledger = worker_assignments.dev_assignment_state()["deliveries"]

    assert ledger["tsk_run"][0]["deviceId"] == "dev_A"
    assert ledger["tsk_run"][0]["state"] == "running"
    assert ledger["tsk_run"][0]["deliveredAt"]
    assert ledger["tsk_fail"][0] == {**ledger["tsk_fail"][0], "state": "failed", "errorCode": "OOM"}
    assert ledger["tsk_done"][0]["state"] == "completed"
    assert ledger["tsk_cancel"][0]["state"] == "cancelled"


def test_monitor_task_rows_exclude_customer_content(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("edgemint.dev.assignment_bridge.enqueue_assignment_for_worker", lambda **_: {})
    workspace_id = fixtures.DEV_WORKSPACE_PRIMARY
    task = fixtures.create_dev_task(
        workspace_id, task_type="text.summarize", input_text="secret customer text"
    )
    try:
        rows = [row for row in fixtures.monitor_task_rows() if row["id"] == task["id"]]
        assert len(rows) == 1
        assert rows[0]["workspaceId"] == str(workspace_id)
        assert rows[0]["taskType"] == "text.summarize"
        assert "secret customer text" not in repr(rows[0])
        assert "inputSource" not in rows[0]
    finally:
        fixtures._created_tasks[workspace_id].remove(task)


def test_build_task_monitor_joins_tasks_deliveries_and_devices() -> None:
    def task(task_id: str, status: str, created: str) -> dict[str, str]:
        return {"id": task_id, "taskType": "text.summarize", "lifecycleStatus": status, "createdAt": created}

    def delivery(device_id: str, state: str, error: str | None) -> dict[str, str | None]:
        return {"deviceId": device_id, "state": state, "errorCode": error, "deliveredAt": "t"}

    tasks = [
        task("tsk_1", "running", "2026-10-28T10:00:00"),
        task("tsk_2", "queued", "2026-10-28T11:00:00"),
        task("tsk_3", "failed", "2026-10-28T09:00:00"),
    ]
    state = {
        "items": [{"taskId": "tsk_2", "assignmentId": "tsk_2"}],
        "exclusiveDeviceId": "dev_A",
        "deliveries": {
            "tsk_1": [delivery("dev_A", "running", None)],
            "tsk_3": [delivery("dev_unknown", "failed", "OOM")],
        },
    }
    devices = {
        "dev_A": {
            "workerId": "wrk_1",
            "platform": "android",
            "deviceTier": "B",
            "deviceName": "Samsung Galaxy S24",
        }
    }
    assert device_ids_in(state) == ["dev_A", "dev_unknown"]

    result = build_task_monitor(tasks, state, devices)

    assert [item["id"] for item in result["items"]] == ["tsk_2", "tsk_1", "tsk_3"]
    by_id = {item["id"]: item for item in result["items"]}
    assert by_id["tsk_1"]["devices"][0]["workerId"] == "wrk_1"
    assert by_id["tsk_1"]["devices"][0]["platform"] == "android"
    assert by_id["tsk_1"]["devices"][0]["deviceName"] == "Samsung Galaxy S24"
    assert by_id["tsk_2"]["inWorkerQueue"] is True
    assert by_id["tsk_2"]["devices"] == []
    assert by_id["tsk_3"]["devices"][0]["workerId"] is None
    assert result["summary"] == {
        "total": 3,
        "byStatus": {"running": 1, "queued": 1, "failed": 1},
        "queueDepth": 1,
        "running": 1,
        "failedDeliveries": 1,
        "pinnedDeviceId": "dev_A",
        "pinnedDeviceName": "Samsung Galaxy S24",
    }


def test_internal_cancel_marks_task_cancelled_and_drops_worker_queue(monkeypatch: pytest.MonkeyPatch) -> None:
    from fastapi import HTTPException

    from edgemint.dev.dev_worker_api import cancel_monitor_task

    monkeypatch.setattr(
        "edgemint.dev.assignment_bridge.enqueue_assignment_for_worker",
        lambda **_: {},
    )
    monkeypatch.setattr(
        "edgemint.dev.assignment_bridge.cancel_assignment_for_worker",
        lambda **_: None,
    )
    workspace_id = fixtures.DEV_WORKSPACE_PRIMARY
    task = fixtures.create_dev_task(workspace_id, task_type="text.summarize", input_text="cancel me")
    try:
        cancelled = cancel_monitor_task(task["id"])
        assert cancelled["lifecycleStatus"] == "cancelled"
        assert cancelled["executionStatus"] == "cancelled"
        assert cancelled["workspaceId"] == str(workspace_id)
    finally:
        fixtures._created_tasks[workspace_id].remove(task)

    with pytest.raises(HTTPException) as raised:
        cancel_monitor_task("tsk_missing")
    assert raised.value.status_code == 404


def test_device_record_prefers_heartbeat_model_over_registration() -> None:
    record = device_record_from_row(
        {
            "worker_public_id": "wrk_1",
            "platform": "android",
            "device_tier": "T4",
            "device_capability": {"device": {"manufacturer": "samsung", "model": "old"}},
            "heartbeat_capability": {
                "device": {"manufacturer": "samsung", "model": "SM-S928B", "name": "Amirmahdi"}
            },
        }
    )
    assert record["deviceName"] == "Samsung SM-S928B"
    assert record["workerId"] == "wrk_1"


def test_unknown_workspace_tasks_are_listed() -> None:
    workspace_id = uuid4()
    fixtures._created_tasks[workspace_id] = [
        {"id": "tsk_x", "taskType": "text.summarize", "lifecycleStatus": "queued", "inputText": "private"}
    ]
    try:
        rows = [row for row in fixtures.monitor_task_rows() if row["id"] == "tsk_x"]
        assert rows == [
            {
                "id": "tsk_x",
                "taskType": "text.summarize",
                "lifecycleStatus": "queued",
                "workspaceId": str(workspace_id),
            }
        ]
    finally:
        del fixtures._created_tasks[workspace_id]
