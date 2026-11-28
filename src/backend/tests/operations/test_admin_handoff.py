from __future__ import annotations

from collections.abc import Iterator
from typing import Any

import pytest
from edgemint.building_blocks.settings import get_settings
from edgemint.operations.admin_handoff import issue_admin_handoff, redeem_admin_handoff, reset_admin_handoffs
from edgemint.services.operations import app
from fastapi.testclient import TestClient


@pytest.fixture(autouse=True)
def _clean_handoffs() -> Iterator[None]:
    reset_admin_handoffs()
    yield
    reset_admin_handoffs()


def test_handoff_round_trip() -> None:
    code, ttl = issue_admin_handoff(email="boss@example.com", role="operator.approver")
    assert ttl > 0
    handoff = redeem_admin_handoff(code)
    assert handoff.email == "boss@example.com"
    assert handoff.role == "operator.approver"
    # Signed tokens are verifiable by any service sharing the JWT secret.
    again = redeem_admin_handoff(code)
    assert again.email == handoff.email
    with pytest.raises(ValueError):
        redeem_admin_handoff("not-a-valid-token")


@pytest.fixture
def handoff_api(monkeypatch: pytest.MonkeyPatch) -> Iterator[dict[str, Any]]:
    monkeypatch.setenv("EDGEMINT_ENVIRONMENT", "test")
    get_settings.cache_clear()
    yield {}
    get_settings.cache_clear()


def test_handoff_login_issues_operator_session(handoff_api: dict[str, Any]) -> None:
    code, _ = issue_admin_handoff(email="boss@example.com", role="operator.break_glass")
    client = TestClient(app)
    response = client.post(
        "/internal/operations/session:handoff",
        json={"handoffCode": code},
    )
    assert response.status_code == 201
    body = response.json()
    assert body["operatorId"] == "boss@example.com"
    assert body["role"] == "operator.break_glass"
    assert client.get("/internal/operations/views/workers").status_code == 200


def test_invalid_handoff_is_rejected(handoff_api: dict[str, Any]) -> None:
    client = TestClient(app)
    response = client.post(
        "/internal/operations/session:handoff",
        json={"handoffCode": "missing"},
    )
    assert response.status_code == 401
    assert response.json()["code"] == "HANDOFF_INVALID"
