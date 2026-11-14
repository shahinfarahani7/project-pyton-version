from __future__ import annotations

from uuid import UUID

import pytest

from edgemint.dev import fixtures


def test_portal_workspace_starts_with_one_million_fibon_tokens() -> None:
    from edgemint.economy.fibonai_token import cached_economy

    fixtures._fibonai_available.pop(fixtures.DEV_WORKSPACE_PRIMARY, None)
    atomic = fixtures.fibonai_available(fixtures.DEV_WORKSPACE_PRIMARY)
    assert atomic == 1_000_000 * cached_economy().atomic_units_per_token


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


def test_add_dev_wallet_credits_whole_fibon_tokens() -> None:
    workspace_id = UUID(int=7)
    fixtures._added_wallets.pop(workspace_id, None)
    fixtures._fibonai_available[workspace_id] = 0
    created = fixtures.add_dev_wallet(workspace_id, name=" Ops ", amount_fibon_atomic=5 * 10_000)
    listed = fixtures.dev_wallets(workspace_id)
    assert created["availableFibonAtomic"] == 50_000
    assert created["name"] == "Ops"
    assert fixtures.fibonai_available(workspace_id) == 50_000
    assert listed["items"][0]["id"] == "wal_primary"
    assert listed["items"][0]["availableFibonAtomic"] == 0
    assert listed["items"][-1]["id"] == created["id"]
    assert listed["items"][-1]["availableFibonAtomic"] == 50_000
    assert sum(item["availableFibonAtomic"] for item in listed["items"]) == 50_000
    with pytest.raises(ValueError, match="WALLET_AMOUNT_INVALID"):
        fixtures.add_dev_wallet(workspace_id, name="Ops", amount_fibon_atomic=0)
    with pytest.raises(ValueError, match="WALLET_AMOUNT_INVALID"):
        fixtures.add_dev_wallet(workspace_id, name="Ops", amount_fibon_atomic=10_001)
    fixtures._added_wallets.pop(workspace_id, None)
    fixtures._fibonai_available.pop(workspace_id, None)


def test_dev_billing_payloads() -> None:
    usage = fixtures.dev_usage(fixtures.DEV_WORKSPACE_PRIMARY)
    balance = fixtures.dev_credit_balance(fixtures.DEV_WORKSPACE_PRIMARY)
    invoices = fixtures.dev_invoices(fixtures.DEV_WORKSPACE_PRIMARY)
    assert usage["status"] == "ready"
    assert usage["computeFibonAtomic"] >= 0
    assert balance["availableFibonAtomic"] == fixtures.fibonai_available(fixtures.DEV_WORKSPACE_PRIMARY)
    assert balance["reservedFibonAtomic"] == fixtures.fibonai_reserved(fixtures.DEV_WORKSPACE_PRIMARY)
    assert "availableMicroEur" not in balance
    assert "computeMicroEur" not in usage
    assert isinstance(invoices["items"], list)


def test_dev_principal_constant() -> None:
    assert fixtures.is_dev_principal(fixtures.DEV_PRINCIPAL_ID)
    assert not fixtures.is_dev_principal(UUID(int=99))


def test_issued_api_key_authenticates_tasks_until_revoked() -> None:
    workspace_id = UUID(int=42)
    fixtures.api_key_directory.forget_workspace(workspace_id)
    created = fixtures.issue_dev_api_key(workspace_id, name=" Partner ")
    assert created["name"] == "Partner"
    assert created["secret"].startswith("emk_")
    assert created["prefix"] == created["secret"][:11]
    assert created["scopes"] == ["customer.tasks:read", "customer.tasks:write"]

    listed = fixtures.dev_api_keys(workspace_id)
    published = next(item for item in listed["items"] if item["id"] == created["id"])
    assert "secret" not in published
    assert "secretHash" not in published

    authenticated = fixtures.authenticate_dev_api_key(created["secret"])
    assert authenticated is not None
    assert authenticated["workspaceId"] == workspace_id
    assert fixtures.authenticate_dev_api_key(created["secret"] + "x") is None
    assert fixtures.authenticate_dev_api_key("") is None

    revoked = fixtures.revoke_dev_api_key(workspace_id, created["id"])
    assert revoked is not None
    assert revoked["status"] == "revoked"
    assert fixtures.authenticate_dev_api_key(created["secret"]) is None
    with pytest.raises(ValueError, match="API_KEY_NAME_INVALID"):
        fixtures.issue_dev_api_key(workspace_id, name="   ")
    fixtures.api_key_directory.forget_workspace(workspace_id)
