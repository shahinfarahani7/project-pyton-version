from __future__ import annotations

from collections.abc import Iterator

import jwt
import pytest
from edgemint.building_blocks.settings import get_settings
from edgemint.operations.auth import cookie_name
from edgemint.services import operations as operations_module
from edgemint.services.operations import app
from fastapi.testclient import TestClient


@pytest.fixture(autouse=True)
def _dev_environment(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    monkeypatch.setenv("EDGEMINT_ENVIRONMENT", "test")
    monkeypatch.delenv("EDGEMINT_JWT_SIGNING_SECRET", raising=False)
    get_settings.cache_clear()
    monkeypatch.setattr(operations_module, "operations_service", operations_module.OperationsService())
    yield
    get_settings.cache_clear()


def _login(client: TestClient, *, operator_id: str = "op_1", role: str = "operator.approver") -> str:
    response = client.post(
        "/internal/operations/session:dev-login",
        json={"operatorId": operator_id, "role": role},
    )
    assert response.status_code == 201
    return response.headers["X-CSRF-Token"]


def test_views_reject_unauthenticated_requests() -> None:
    client = TestClient(app)
    response = client.get("/internal/operations/views/workers")
    assert response.status_code == 401
    assert response.json()["code"] == "AUTH_REQUIRED"
    assert client.get("/internal/operations/worker-devices").status_code == 401
    assert client.get("/internal/operations/audit-log").status_code == 401


def test_forged_session_token_is_rejected() -> None:
    client = TestClient(app)
    forged = jwt.encode(
        {
            "sub": "op_x",
            "role": "operator.break_glass",
            "mfa": True,
            "csrf": "c",
            "iat": 1,
            "exp": 9_999_999_999,
        },
        "attacker-secret",
        algorithm="HS256",
    )
    client.cookies.set(cookie_name(get_settings()), forged)
    assert client.get("/internal/operations/views/workers").status_code == 401


def test_authenticated_operator_can_read_and_session_is_restorable() -> None:
    client = TestClient(app)
    _login(client)
    assert client.get("/internal/operations/views/workers").status_code == 200
    session = client.get("/internal/operations/session")
    assert session.status_code == 200
    assert session.json()["operatorId"] == "op_1"
    assert session.headers["X-CSRF-Token"]


def test_mutation_requires_csrf_header() -> None:
    client = TestClient(app)
    csrf = _login(client, role="operator.standard")
    body = {
        "action": "task.requeue",
        "resourceId": "tsk_ops_1",
        "reasonCode": "incident_response",
        "ticketId": "INC-1",
    }
    missing = client.post("/internal/operations/actions:submit", json=body)
    assert missing.status_code == 403
    assert missing.json()["code"] == "CSRF_INVALID"
    ok = client.post("/internal/operations/actions:submit", json=body, headers={"X-CSRF-Token": csrf})
    assert ok.status_code == 200


def test_role_comes_from_session_not_request_body() -> None:
    client = TestClient(app)
    csrf = _login(client, role="operator.readonly")
    response = client.post(
        "/internal/operations/break-glass:activate",
        json={
            "reasonCode": "incident_response",
            "ticketId": "INC-2",
            "role": "operator.break_glass",
            "operatorId": "op_admin",
        },
        headers={"X-CSRF-Token": csrf},
    )
    assert response.status_code == 403
    assert response.json()["code"] == "AUTH_SCOPE_REQUIRED"


def test_self_approval_uses_session_identity() -> None:
    requester = TestClient(app)
    csrf = _login(requester, operator_id="op_req", role="operator.approver")
    pending = requester.post(
        "/internal/operations/actions:submit",
        json={
            "action": "worker.quarantine",
            "resourceId": "wrk_ops_1",
            "reasonCode": "fraud_investigation",
            "ticketId": "FRD-1",
        },
        headers={"X-CSRF-Token": csrf},
    )
    assert pending.status_code == 202
    approval_id = pending.json()["approvalId"]
    self_approve = requester.post(
        f"/internal/operations/approvals/{approval_id}:approve",
        json={"approverId": "someone_else"},
        headers={"X-CSRF-Token": csrf},
    )
    assert self_approve.status_code == 403
    assert self_approve.json()["code"] == "APPROVAL_SELF_DENIED"


def test_dev_login_disabled_outside_development(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("EDGEMINT_ENVIRONMENT", "production")
    monkeypatch.setenv("EDGEMINT_JWT_SIGNING_SECRET", "prod-secret")
    get_settings.cache_clear()
    client = TestClient(app)
    response = client.post("/internal/operations/session:dev-login", json={})
    assert response.status_code == 404
    assert response.json()["code"] == "DEV_LOGIN_DISABLED"
