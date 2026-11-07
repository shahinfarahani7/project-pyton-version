from __future__ import annotations

from unittest.mock import patch

from edgemint.dev import fixtures
from edgemint.economy.fibonai_token import quote_accepted_task


def test_portal_task_reserves_fibonai_and_records_the_worker_reward() -> None:
    workspace_id = fixtures.DEV_WORKSPACE_STAGING
    before = fixtures.fibonai_available(workspace_id)
    quote = quote_accepted_task()
    with patch("edgemint.dev.assignment_bridge.enqueue_assignment_for_worker", return_value={}):
        task = fixtures.create_dev_task(workspace_id, task_type="text.summarize", input_text="hello")
    assert task["fibonaiChargeAtomic"] == quote.charge_atomic
    assert task["fibonaiWorkerRewardAtomic"] == quote.worker_reward_atomic
    assert task["fibonaiSettlement"] == "reserved"
    assert fixtures.fibonai_available(workspace_id) == before - quote.charge_atomic
    assert fixtures.fibonai_reserved(workspace_id) >= quote.charge_atomic


def test_cancel_refunds_the_reserved_fibonai() -> None:
    workspace_id = fixtures.DEV_WORKSPACE_STAGING
    with patch("edgemint.dev.assignment_bridge.enqueue_assignment_for_worker", return_value={}):
        task = fixtures.create_dev_task(workspace_id, task_type="text.summarize", input_text="hello")
    charged = fixtures.fibonai_available(workspace_id)
    cancelled = fixtures.cancel_dev_task(workspace_id, task["id"])
    assert cancelled is not None
    assert cancelled["fibonaiSettlement"] == "refunded"
    assert fixtures.fibonai_available(workspace_id) == charged + cancelled["fibonaiChargeAtomic"]


def test_failed_task_refunds_and_success_keeps_the_charge() -> None:
    workspace_id = fixtures.DEV_WORKSPACE_STAGING
    with patch("edgemint.dev.assignment_bridge.enqueue_assignment_for_worker", return_value={}):
        failed = fixtures.create_dev_task(workspace_id, task_type="text.summarize", input_text="hello")
        succeeded = fixtures.create_dev_task(workspace_id, task_type="text.summarize", input_text="hello")
    after_create = fixtures.fibonai_available(workspace_id)
    assert fixtures.reject_dev_task_output(failed["id"], reason_code="RUNTIME_CRASH", reason_detail="boom")
    assert fixtures.fibonai_available(workspace_id) == after_create + failed["fibonaiChargeAtomic"]
    assert fixtures.update_dev_task_execution(
        succeeded["id"],
        lifecycle_status="succeeded",
        execution_status="succeeded",
    )
    assert succeeded["fibonaiSettlement"] == "spent"
    assert fixtures.fibonai_available(workspace_id) == after_create + failed["fibonaiChargeAtomic"]


def test_empty_balance_rejects_the_task() -> None:
    workspace_id = fixtures.DEV_WORKSPACE_PRIMARY
    previous = fixtures.fibonai_available(workspace_id)
    fixtures._fibonai_available[workspace_id] = 0
    try:
        with patch("edgemint.dev.assignment_bridge.enqueue_assignment_for_worker", return_value={}):
            try:
                fixtures.create_dev_task(workspace_id, task_type="text.summarize", input_text="hello")
            except ValueError as exc:
                assert str(exc) == "INSUFFICIENT_FIBONAI"
            else:
                raise AssertionError("expected INSUFFICIENT_FIBONAI")
    finally:
        fixtures._fibonai_available[workspace_id] = previous
