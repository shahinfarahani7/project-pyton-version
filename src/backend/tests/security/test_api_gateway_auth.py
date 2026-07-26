from __future__ import annotations

import os
from uuid import UUID

import pytest
from edgemint.building_blocks.settings import Settings
from edgemint.services import api_gateway
from fastapi.testclient import TestClient

pytestmark = pytest.mark.filterwarnings("ignore::jwt.InsecureKeyLengthWarning")
TEST_SIGNING_SECRET = "x" * 32


def _postgres_available() -> bool:
    return bool(os.environ.get("EDGEMINT_DATABASE_URL"))


requires_postgres = pytest.mark.skipif(not _postgres_available(), reason="PostgreSQL not available")


@pytest.fixture
def gateway_client(monkeypatch: pytest.MonkeyPatch) -> TestClient:
    monkeypatch.setattr(
        api_gateway,
        "settings",
        Settings(
            _env_file=None,
            environment="test",
            jwt_signing_secret=TEST_SIGNING_SECRET,
            database_url=os.environ.get("EDGEMINT_DATABASE_URL"),
        ),
    )
    return TestClient(api_gateway.app)


def test_auth_health_reports_ready(gateway_client: TestClient) -> None:
    response = gateway_client.get("/auth/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ready"


@requires_postgres
def test_create_session_and_issue_delegated_token(gateway_client: TestClient) -> None:
    principal_id = UUID(int=10)
    workspace_id = UUID(int=11)
    create = gateway_client.post(
        "/auth/sessions",
        json={
            "principalId": str(principal_id),
            "workspaceId": str(workspace_id),
            "permissions": ["customer.tasks:read"],
        },
    )
    assert create.status_code == 200, create.text
    body = create.json()
    assert body["workspaceId"] == str(workspace_id)
    assert create.cookies.get("__Host-edgemint-session")

    token_response = gateway_client.post("/auth/delegated-token")
    assert token_response.status_code == 200, token_response.text
    token_body = token_response.json()
    assert token_body["accessToken"]
    assert token_body["tokenType"] == "Bearer"
