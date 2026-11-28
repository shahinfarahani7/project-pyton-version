from __future__ import annotations

from collections.abc import AsyncIterator, Iterator
from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

import pytest
from edgemint.building_blocks.settings import Settings, get_settings
from edgemint.operations.portal_admin import admin_roles
from edgemint.security.tokens import BrowserSessionRecord, BrowserSessionStore
from edgemint.services import operations as operations_module
from edgemint.services.operations import app
from fastapi.testclient import TestClient

PRINCIPAL = UUID("00000000-0000-0000-0000-0000000000b1")
PORTAL_TOKEN = "portal-token"  # noqa: S105


def _record(*, revoked: bool = False) -> BrowserSessionRecord:
    now = datetime.now(UTC)
    return BrowserSessionRecord(
        session_id=UUID(int=1),
        public_id="ses_1",
        principal_id=PRINCIPAL,
        workspace_id=UUID(int=2),
        authorization_generation=1,
        risk_state="normal",
        revoked=revoked,
        absolute_expires_at=now + timedelta(hours=1),
        idle_expires_at=now + timedelta(minutes=30),
    )


@pytest.fixture
def portal(monkeypatch: pytest.MonkeyPatch) -> Iterator[dict[str, Any]]:
    state: dict[str, Any] = {"record": _record(), "email": "boss@example.com"}
    monkeypatch.setenv("EDGEMINT_ENVIRONMENT", "test")
    monkeypatch.setenv("EDGEMINT_OPERATIONS_ADMIN_EMAILS", "boss@example.com=operator.break_glass")
    get_settings.cache_clear()

    @asynccontextmanager
    async def fake_transaction(**_: Any) -> AsyncIterator[object]:
        yield object()

    async def fake_load(self: BrowserSessionStore, _conn: object, *, session_token: str) -> Any:
        return state["record"] if session_token == PORTAL_TOKEN else None

    async def fake_email(_conn: object, principal_id: UUID) -> str | None:
        return state["email"] if principal_id == PRINCIPAL else None

    async def fake_resolve(
        _conn: object, settings: Settings, email: str | None
    ) -> str | None:
        managed = state.get("managed_roles", {})
        if email and email in managed:
            return managed[email]
        return admin_roles(settings).get(email) if email else None

    monkeypatch.setattr(operations_module, "transaction", fake_transaction)
    monkeypatch.setattr(BrowserSessionStore, "load_by_token", fake_load)
    monkeypatch.setattr(operations_module, "portal_email_for_principal", fake_email)
    monkeypatch.setattr(operations_module, "resolve_admin_role", fake_resolve)
    yield state
    get_settings.cache_clear()


def _client(with_portal_cookie: bool = True) -> TestClient:
    client = TestClient(app)
    if with_portal_cookie:
        client.cookies.set(BrowserSessionStore.DEV_SESSION_COOKIE, PORTAL_TOKEN)
    return client


def test_portal_admin_gets_operator_session_with_configured_role(portal: dict[str, Any]) -> None:
    client = _client()
    response = client.post("/internal/operations/session:portal")
    assert response.status_code == 201
    assert response.json()["operatorId"] == "boss@example.com"
    assert response.json()["role"] == "operator.break_glass"
    assert client.get("/internal/operations/views/workers").status_code == 200


def test_portal_user_not_in_admin_list_is_rejected(portal: dict[str, Any]) -> None:
    portal["email"] = "customer@example.com"
    client = _client()
    response = client.post("/internal/operations/session:portal")
    assert response.status_code == 403
    assert client.get("/internal/operations/views/workers").status_code == 401


def test_portal_admin_from_managed_list_is_accepted(portal: dict[str, Any]) -> None:
    portal["email"] = "new-admin@example.com"
    portal["managed_roles"] = {"new-admin@example.com": "operator.approver"}
    client = _client()
    response = client.post("/internal/operations/session:portal")
    assert response.status_code == 201
    assert response.json()["operatorId"] == "new-admin@example.com"
    assert response.json()["role"] == "operator.approver"


def test_missing_or_revoked_portal_session_is_rejected(portal: dict[str, Any]) -> None:
    assert _client(with_portal_cookie=False).post("/internal/operations/session:portal").status_code == 401
    portal["record"] = _record(revoked=True)
    response = _client().post("/internal/operations/session:portal")
    assert response.status_code == 401
    assert response.json()["code"] == "PORTAL_SESSION_REQUIRED"


def test_portal_login_disabled_in_production(portal: dict[str, Any], monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("EDGEMINT_ENVIRONMENT", "production")
    monkeypatch.setenv("EDGEMINT_JWT_SIGNING_SECRET", "prod-secret-that-is-long-enough-for-hs256")
    get_settings.cache_clear()
    assert _client().post("/internal/operations/session:portal").status_code == 404


def test_admin_roles_parsing() -> None:
    settings = Settings(
        environment="test",
        operations_admin_emails=" A@Example.com , b@example.com=operator.readonly",
    )
    assert admin_roles(settings) == {
        "a@example.com": "operator.approver",
        "b@example.com": "operator.readonly",
    }
    assert admin_roles(Settings(environment="development")) == {
        "dev-user@edgemint.local": "operator.approver",
    }
    assert admin_roles(Settings(environment="test")) == {}
    with pytest.raises(ValueError):
        admin_roles(Settings(environment="test", operations_admin_emails="x@example.com=root"))
