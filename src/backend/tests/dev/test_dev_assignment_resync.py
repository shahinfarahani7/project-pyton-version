from edgemint.dev import worker_assignments


def test_claimed_task_counts_as_open_for_resync() -> None:
    worker_assignments._pending.clear()
    worker_assignments._completed.clear()
    worker_assignments._delivered_devices.clear()
    worker_assignments._in_flight_devices.clear()
    worker_assignments._failed_devices.clear()
    worker_assignments._cancelled_ids.clear()

    worker_assignments.enqueue_dev_assignment(
        task_id="tsk_dev_once",
        task_type="text.direct",
    )
    claimed = worker_assignments.claim_next_assignment(device_public_id="dev_phone")
    assert claimed is not None
    assert worker_assignments.list_pending_assignments() == []
    assert "tsk_dev_once" in worker_assignments.task_ids_with_open_dev_assignments()
