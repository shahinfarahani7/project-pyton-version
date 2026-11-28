from __future__ import annotations

from collections.abc import Iterator
from datetime import UTC, datetime
from typing import Any
from urllib.parse import quote

import pytest
from edgemint.building_blocks.settings import Settings, get_settings
from edgemint.operations.portal_admin import (
    admin_roles,
    list_admin_entries,
    normalize_admin_email,
)
from edgemint.services import operations as operations_module
from edgemint.services.operations import app
from fastapi.testclient import TestClient


def test_normalize_admin_email() -> None:
    assert normalize_admin_email("  Boss@Example.COM ") == "boss@example.com"
    with pytest.raises(ValueError):
        normalize_admin_email("not-an-email")


@pytest.mark.asyncio
async def test_list_admin_entries_merges_env_and_managed() -> None:
    settings = Settings(
        environment="test",
        operations_admin_emails="seed@example.com=operator.readonly",
    )
    managed = [
        {
            "email": "seed@example.com",
            "role": "operator.break_glass",
            "created_by": "boss@example.com",
            "updated_at_utc": datetime(2026, 11, 28, tzinfo=UTC),
        },
        {
            "email": "added@example.com",
            "role": "operator.approver",
            "created_by": "boss@example.com",
            "updated_at_utc": datetime(2026, 11, 28, tzinfo=UTC),
        },
    ]

    class _Conn:
        pass

    async def fake_rows(_conn: object) -> list[dict[str, Any]]:
        return managed

    monkeypatch = pytest.MonkeyPatch()
    monkeypatch.setattr(
        "edgemint.operations.portal_admin._load_managed_rows",
        fake_rows,
    )
    try:
        items = await list_admin_entries(_Conn(), settings)
    finally:
        monkeypatch.undo()

    by_email = {item["email"]: item for item in items}
    assert by_email["seed@example.com"]["source"] == "managed"
    assert by_email["seed@example.com"]["role"] == "operator.break_glass"
    assert by_email["seed@example.com"]["overridesEnvironment"] is True
    assert by_email["added@example.com"]["editable"] is True
    assert admin_roles(settings)["seed@example.com"] == "operator.readonly"


@pytest.fixture
def admin_api(monkeypatch: pytest.MonkeyPatch) -> Iterator[dict[str, Any]]:
    state: dict[str, Any] = {
        "rows": {},
    }
    monkeypatch.setenv("EDGEMINT_ENVIRONMENT", "test")
    monkeypatch.setenv("EDGEMINT_OPERATIONS_ADMIN_EMAILS", "boss@example.com=operator.approver")
    get_settings.cache_clear()

    from contextlib import asynccontextmanager

    @asynccontextmanager
    async def fake_transaction(**_: Any):
        yield object()

    async def fake_list(_conn: object, settings: Settings) -> list[dict[str, Any]]:
        items = []
        for email, role in admin_roles(settings).items():
            managed = state["rows"].get(email)
            if managed:
                items.append({**managed, "overridesEnvironment": True})
            else:
                items.append(
                    {
                        "email": email,
                        "role": role,
                        "source": "environment",
                        "editable": False,
                        "overridesEnvironment": False,
                        "createdBy": None,
                        "updatedAt": None,
                    }
                )
        for email, row in state["rows"].items():
            if email in admin_roles(settings):
                continue
            items.append({**row, "overridesEnvironment": False})
        return sorted(items, key=lambda item: item["email"])

    async def fake_upsert(
        _conn: object, *, email: str, role: str, created_by: str
    ) -> dict[str, Any]:
        from edgemint.operations.policy import ROLE_PERMISSIONS
        from edgemint.operations.portal_admin import normalize_admin_email

        if role not in ROLE_PERMISSIONS:
            raise ValueError("UNKNOWN_ROLE")
        normalized = normalize_admin_email(email)
        row = {
            "email": normalized,
            "role": role,
            "source": "managed",
            "editable": True,
            "createdBy": created_by,
            "updatedAt": "2026-11-28T00:00:00+00:00",
        }
        state["rows"][normalized] = row
        return row

    async def fake_delete(_conn: object, *, email: str, actor_id: str) -> bool:
        from edgemint.operations.portal_admin import normalize_admin_email

        normalized = normalize_admin_email(email)
        if normalized == actor_id.strip().lower():
            raise ValueError("CANNOT_REMOVE_SELF")
        return state["rows"].pop(normalized, None) is not None

    monkeypatch.setattr(operations_module, "transaction", fake_transaction)
    monkeypatch.setattr(operations_module, "list_admin_entries", fake_list)
    monkeypatch.setattr(operations_module, "upsert_admin_email", fake_upsert)
    monkeypatch.setattr(operations_module, "delete_admin_email", fake_delete)
    yield state
    get_settings.cache_clear()


def _login(client: TestClient) -> str:
    response = client.post(
        "/internal/operations/session:dev-login",
        json={"operatorId": "boss@example.com", "role": "operator.approver"},
    )
    assert response.status_code == 201
    return response.headers["X-CSRF-Token"]


def test_admin_email_crud(admin_api: dict[str, Any]) -> None:
    client = TestClient(app)
    csrf = _login(client)

    listed = client.get("/internal/operations/admins")
    assert listed.status_code == 200
    assert any(item["email"] == "boss@example.com" for item in listed.json()["items"])

    created = client.post(
        "/internal/operations/admins",
        headers={"X-CSRF-Token": csrf},
        json={"email": "New.Admin@Example.com", "role": "operator.readonly"},
    )
    assert created.status_code == 201
    assert created.json()["email"] == "new.admin@example.com"
    assert "new.admin@example.com" in admin_api["rows"]

    removed = client.delete(
        f"/internal/operations/admins/{quote('new.admin@example.com')}",
        headers={"X-CSRF-Token": csrf},
    )
    assert removed.status_code == 200
    assert "new.admin@example.com" not in admin_api["rows"]


def test_cannot_remove_own_admin_email(admin_api: dict[str, Any]) -> None:
    client = TestClient(app)
    csrf = _login(client)
    admin_api["rows"]["boss@example.com"] = {
        "email": "boss@example.com",
        "role": "operator.approver",
        "source": "managed",
        "editable": True,
        "createdBy": "boss@example.com",
        "updatedAt": "2026-11-28T00:00:00+00:00",
    }
    response = client.delete(
        "/internal/operations/admins/boss@example.com",
        headers={"X-CSRF-Token": csrf},
    )
    assert response.status_code == 409
    assert response.json()["code"] == "ADMIN_SELF_REMOVE_DENIED"


def test_readonly_cannot_add_admin(admin_api: dict[str, Any]) -> None:
    client = TestClient(app)
    login = client.post(
        "/internal/operations/session:dev-login",
        json={"operatorId": "reader@example.com", "role": "operator.readonly"},
    )
    assert login.status_code == 201
    csrf = login.headers["X-CSRF-Token"]
    response = client.post(
        "/internal/operations/admins",
        headers={"X-CSRF-Token": csrf},
        json={"email": "x@example.com", "role": "operator.approver"},
    )
    assert response.status_code == 403
