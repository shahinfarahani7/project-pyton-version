from __future__ import annotations

from uuid import UUID

import pytest

from edgemint.dev import fixtures


def test_dev_workspaces_include_primary_and_staging() -> None:
    workspace_ids = {item["id"] for item in fixtures.dev_workspaces()}
    assert str(fixtures.DEV_WORKSPACE_PRIMARY) in workspace_ids
    assert str(fixtures.DEV_WORKSPACE_STAGING) in workspace_ids


def test_dev_tasks_vary_by_workspace(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(fixtures, "_reconcile_worker_pending_tasks", lambda: [])
    primary = fixtures.dev_tasks(fixtures.DEV_WORKSPACE_PRIMARY)
    staging = fixtures.dev_tasks(fixtures.DEV_WORKSPACE_STAGING)
    assert len(primary["items"]) >= 3
    assert len(staging["items"]) == 1
    assert primary["items"][0]["lifecycleStatus"] == "running"


def test_dev_task_lookup() -> None:
    task = fixtures.dev_task(fixtures.DEV_WORKSPACE_PRIMARY, "tsk_dev_nlp_done")
    assert task is not None
    assert task["executionStatus"] == "completed"
    assert fixtures.dev_task(fixtures.DEV_WORKSPACE_PRIMARY, "missing") is None


def test_add_dev_wallet_stores_integer_micro_eur() -> None:
    workspace_id = UUID(int=7)
    fixtures._added_wallets.pop(workspace_id, None)
    created = fixtures.add_dev_wallet(workspace_id, name=" Ops ", amount_micro_eur=5_000_000)
    listed = fixtures.dev_wallets(workspace_id)
    assert created["availableMicroEur"] == 5_000_000
    assert created["name"] == "Ops"
    assert listed["items"][0]["id"] == "wal_primary"
    assert listed["items"][-1]["id"] == created["id"]
    with pytest.raises(ValueError, match="WALLET_AMOUNT_INVALID"):
        fixtures.add_dev_wallet(workspace_id, name="Ops", amount_micro_eur=0)
    fixtures._added_wallets.pop(workspace_id, None)


def test_dev_billing_payloads() -> None:
    usage = fixtures.dev_usage(fixtures.DEV_WORKSPACE_PRIMARY)
    balance = fixtures.dev_credit_balance(fixtures.DEV_WORKSPACE_PRIMARY)
    invoices = fixtures.dev_invoices(fixtures.DEV_WORKSPACE_PRIMARY)
    assert usage["status"] == "ready"
    assert balance["availableMicroEur"] > 0
    assert len(invoices["items"]) == 2


def test_dev_principal_constant() -> None:
    assert fixtures.is_dev_principal(fixtures.DEV_PRINCIPAL_ID)
    assert not fixtures.is_dev_principal(UUID(int=99))
