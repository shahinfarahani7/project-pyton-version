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


def _invoice(workspace_id, task_id: str) -> dict:
    found = next(item for item in fixtures.dev_invoices(workspace_id)["items"] if item["taskId"] == task_id)
    return found


def test_settlement_opens_pays_and_voids_the_invoice() -> None:
    workspace_id = fixtures.DEV_WORKSPACE_STAGING
    with patch("edgemint.dev.assignment_bridge.enqueue_assignment_for_worker", return_value={}):
        spent = fixtures.create_dev_task(workspace_id, task_type="text.summarize", input_text="hello")
        cancelled = fixtures.create_dev_task(workspace_id, task_type="text.summarize", input_text="hello")
    assert _invoice(workspace_id, spent["id"])["status"] == "open"
    assert _invoice(workspace_id, spent["id"])["amountFibonAtomic"] == spent["fibonaiChargeAtomic"]
    assert len(_invoice(workspace_id, spent["id"])["period"]) == 7
    usage_before = fixtures.dev_usage(workspace_id)["computeFibonAtomic"]
    available_while_open = fixtures.fibonai_available(workspace_id)
    assert fixtures.update_dev_task_execution(
        spent["id"],
        lifecycle_status="succeeded",
        execution_status="succeeded",
    )
    fixtures.cancel_dev_task(workspace_id, cancelled["id"])
    assert _invoice(workspace_id, spent["id"])["status"] == "paid"
    assert _invoice(workspace_id, cancelled["id"])["status"] == "void"
    spent_usage = fixtures.dev_usage(workspace_id)["computeFibonAtomic"]
    assert spent_usage == usage_before + spent["fibonaiChargeAtomic"]
    available_after = fixtures.fibonai_available(workspace_id)
    assert available_after == available_while_open + cancelled["fibonaiChargeAtomic"]
    listed = fixtures.dev_wallets(workspace_id)["items"]
    assert sum(item["availableFibonAtomic"] for item in listed) == fixtures.fibonai_available(workspace_id)
    balance = fixtures.dev_credit_balance(workspace_id)
    assert balance["availableFibonAtomic"] == fixtures.fibonai_available(workspace_id)
    assert balance["reservedFibonAtomic"] == fixtures.fibonai_reserved(workspace_id)


def test_added_wallet_funds_the_next_task() -> None:
    from uuid import UUID

    workspace_id = UUID(int=11)
    quote = quote_accepted_task()
    fixtures._fibonai_available[workspace_id] = 0
    fixtures._added_wallets.pop(workspace_id, None)
    fixtures._billing_invoices.pop(workspace_id, None)
    fixtures._created_tasks.pop(workspace_id, None)
    try:
        fixtures.add_dev_wallet(workspace_id, name="Travel", amount_fibon_atomic=quote.charge_atomic)
        with patch("edgemint.dev.assignment_bridge.enqueue_assignment_for_worker", return_value={}):
            task = fixtures.create_dev_task(workspace_id, task_type="text.summarize", input_text="hello")
        assert task["fibonaiSettlement"] == "reserved"
        assert fixtures.fibonai_available(workspace_id) == 0
        assert _invoice(workspace_id, task["id"])["status"] == "open"
        rows = fixtures.dev_wallets(workspace_id)["items"]
        assert sum(row["availableFibonAtomic"] for row in rows) == 0
    finally:
        fixtures._added_wallets.pop(workspace_id, None)
        fixtures._billing_invoices.pop(workspace_id, None)
        fixtures._created_tasks.pop(workspace_id, None)
        fixtures._fibonai_available.pop(workspace_id, None)


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
