"""Prepaid FIBON book: wallet slices, one settlement, and a balanced journal."""

from __future__ import annotations

from unittest.mock import patch
from uuid import UUID

import pytest
from edgemint.dev import fixtures
from edgemint.dev.fibonai_billing import WorkspaceBook
from edgemint.economy.fibonai_token import quote_accepted_task


def _assert_balanced(book: WorkspaceBook) -> None:
    book.check_invariants()
    for entry in book.journal_entries():
        assert sum(leg.amount for leg in entry.legs) == 0
    for wallet in book.wallets:
        assert wallet.available + wallet.reserved + wallet.spent == wallet.funded


def _isolate(workspace_id: UUID) -> None:
    fixtures.forget_fibonai_book(workspace_id)
    fixtures._created_tasks.pop(workspace_id, None)


def test_primary_wallet_is_drawn_before_a_named_wallet() -> None:
    workspace_id = UUID(int=21)
    quote = quote_accepted_task()
    _isolate(workspace_id)
    try:
        book = fixtures.install_fibonai_book(workspace_id, primary_atomic=quote.charge_atomic * 3)
        named = fixtures.add_dev_wallet(
            workspace_id,
            name="Travel",
            amount_fibon_atomic=quote.charge_atomic,
        )
        with patch("edgemint.dev.assignment_bridge.enqueue_assignment_for_worker", return_value={}):
            task = fixtures.create_dev_task(workspace_id, task_type="text.summarize", input_text="hello")
        rows = {item["id"]: item for item in fixtures.dev_wallets(workspace_id)["items"]}
        assert rows["wal_primary"]["availableFibonAtomic"] == quote.charge_atomic * 2
        assert rows["wal_primary"]["reservedFibonAtomic"] == quote.charge_atomic
        assert rows[named["id"]]["availableFibonAtomic"] == quote.charge_atomic
        assert rows[named["id"]]["reservedFibonAtomic"] == 0
        posting = book.posting_for(task["id"])
        assert posting is not None
        assert [(item.wallet_id, item.amount) for item in posting.slices] == [
            ("wal_primary", quote.charge_atomic)
        ]
        _assert_balanced(book)
    finally:
        _isolate(workspace_id)


def test_short_primary_draws_the_oldest_named_wallet_and_cancel_returns_the_slices() -> None:
    workspace_id = UUID(int=22)
    quote = quote_accepted_task()
    primary_part = quote.charge_atomic // 2
    rest = quote.charge_atomic - primary_part
    _isolate(workspace_id)
    try:
        book = fixtures.install_fibonai_book(workspace_id, primary_atomic=primary_part)
        older = fixtures.add_dev_wallet(workspace_id, name="Older", amount_fibon_atomic=quote.charge_atomic)
        newer = fixtures.add_dev_wallet(workspace_id, name="Newer", amount_fibon_atomic=quote.charge_atomic)
        with patch("edgemint.dev.assignment_bridge.enqueue_assignment_for_worker", return_value={}):
            task = fixtures.create_dev_task(workspace_id, task_type="text.summarize", input_text="hello")
        posting = book.posting_for(task["id"])
        assert posting is not None
        assert [(item.wallet_id, item.amount) for item in posting.slices] == [
            ("wal_primary", primary_part),
            (older["id"], rest),
        ]
        journal_after_reserve = len(book.journal_entries())
        cancelled = fixtures.cancel_dev_task(workspace_id, task["id"])
        assert cancelled is not None
        assert cancelled["fibonaiSettlement"] == "refunded"
        assert posting.status == "released"
        rows = {item["id"]: item for item in fixtures.dev_wallets(workspace_id)["items"]}
        assert rows["wal_primary"]["availableFibonAtomic"] == primary_part
        assert rows["wal_primary"]["reservedFibonAtomic"] == 0
        assert rows[older["id"]]["availableFibonAtomic"] == quote.charge_atomic
        assert rows[older["id"]]["reservedFibonAtomic"] == 0
        assert rows[newer["id"]]["availableFibonAtomic"] == quote.charge_atomic
        assert rows[newer["id"]]["reservedFibonAtomic"] == 0
        assert len(book.journal_entries()) > journal_after_reserve
        frozen = len(book.journal_entries())
        assert book.settle(task["id"], "cancelled", now="2026-11-14T00:00:00+00:00") is not None
        assert len(book.journal_entries()) == frozen
        _assert_balanced(book)
    finally:
        _isolate(workspace_id)


def test_two_named_wallets_fund_one_task_when_their_sum_covers_the_quote() -> None:
    workspace_id = UUID(int=23)
    quote = quote_accepted_task()
    first = quote.charge_atomic // 2
    second = quote.charge_atomic - first
    _isolate(workspace_id)
    try:
        book = fixtures.install_fibonai_book(workspace_id, primary_atomic=0)
        older = fixtures.add_dev_wallet(workspace_id, name="Older", amount_fibon_atomic=first)
        newer = fixtures.add_dev_wallet(workspace_id, name="Newer", amount_fibon_atomic=second)
        with patch("edgemint.dev.assignment_bridge.enqueue_assignment_for_worker", return_value={}):
            task = fixtures.create_dev_task(workspace_id, task_type="text.summarize", input_text="hello")
        assert task["fibonaiSettlement"] == "reserved"
        assert fixtures.fibonai_available(workspace_id) == 0
        assert fixtures.fibonai_reserved(workspace_id) == quote.charge_atomic
        posting = book.posting_for(task["id"])
        assert posting is not None
        assert [item.wallet_id for item in posting.slices] == [older["id"], newer["id"]]
        rows = {item["id"]: item for item in fixtures.dev_wallets(workspace_id)["items"]}
        assert rows["wal_primary"]["reservedFibonAtomic"] == 0
        assert rows[older["id"]]["reservedFibonAtomic"] == first
        assert rows[newer["id"]]["reservedFibonAtomic"] == second
        _assert_balanced(book)
    finally:
        _isolate(workspace_id)


def test_settling_a_spent_task_again_posts_nothing() -> None:
    workspace_id = UUID(int=24)
    quote = quote_accepted_task()
    _isolate(workspace_id)
    try:
        book = fixtures.install_fibonai_book(workspace_id, primary_atomic=quote.charge_atomic)
        with patch("edgemint.dev.assignment_bridge.enqueue_assignment_for_worker", return_value={}):
            task = fixtures.create_dev_task(workspace_id, task_type="text.summarize", input_text="hello")
        reserved_entries = len(book.journal_entries())
        assert fixtures.update_dev_task_execution(
            task["id"],
            lifecycle_status="succeeded",
            execution_status="succeeded",
        )
        spent_entries = len(book.journal_entries())
        assert spent_entries > reserved_entries
        available = fixtures.fibonai_available(workspace_id)
        assert fixtures.update_dev_task_execution(
            task["id"],
            lifecycle_status="succeeded",
            execution_status="succeeded",
        )
        assert fixtures.update_dev_task_execution(
            task["id"],
            lifecycle_status="failed",
            execution_status="failed",
        )
        assert task["fibonaiSettlement"] == "spent"
        assert fixtures.fibonai_available(workspace_id) == available
        assert fixtures.fibonai_reserved(workspace_id) == 0
        assert len(book.journal_entries()) == spent_entries
        invoices = fixtures.dev_invoices(workspace_id)["items"]
        invoice = next(item for item in invoices if item["taskId"] == task["id"])
        assert invoice["status"] == "paid"
        assert invoice["amountFibonAtomic"] == quote.charge_atomic
        _assert_balanced(book)
    finally:
        _isolate(workspace_id)


def test_empty_balance_rejects_the_task_without_a_posting() -> None:
    workspace_id = UUID(int=25)
    _isolate(workspace_id)
    try:
        book = fixtures.install_fibonai_book(workspace_id, primary_atomic=0)
        with patch("edgemint.dev.assignment_bridge.enqueue_assignment_for_worker", return_value={}):
            with pytest.raises(ValueError, match="INSUFFICIENT_FIBONAI"):
                fixtures.create_dev_task(workspace_id, task_type="text.summarize", input_text="hello")
        assert book.postings == {}
        assert book.journal_entries() == ()
        assert workspace_id not in fixtures._created_tasks
        _assert_balanced(book)
    finally:
        _isolate(workspace_id)


def test_mismatched_reward_split_does_not_move_funds() -> None:
    book = WorkspaceBook.open(UUID(int=26), grant_atomic=100)
    with pytest.raises(ValueError, match="BILLING_SPLIT_MISMATCH"):
        book.reserve(
            "tsk_bad",
            difficulty_grade=1,
            charge_atomic=10,
            worker_reward_atomic=3,
            treasury_atomic=3,
            now="2026-11-14T00:00:00+00:00",
        )
    assert book.available_total() == 100
    assert book.postings == {}
    _assert_balanced(book)
