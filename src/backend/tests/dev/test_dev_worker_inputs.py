from __future__ import annotations

import os

import pytest
from edgemint.building_blocks.settings import Settings
from edgemint.dev import fixtures
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


@requires_postgres
def test_worker_ocr_input_and_output_roundtrip(gateway_client: TestClient) -> None:
    login = gateway_client.post(
        "/auth/sessions",
        json={
            "principalId": str(fixtures.DEV_PRINCIPAL_ID),
            "workspaceId": str(fixtures.DEV_WORKSPACE_PRIMARY),
            "permissions": ["customer.tasks:read", "customer.tasks:write"],
        },
    )
    assert login.status_code == 200, login.text

    created = gateway_client.post(
        f"/v1/workspaces/{fixtures.DEV_WORKSPACE_PRIMARY}/tasks",
        json={"taskType": "document.ocr"},
    )
    assert created.status_code == 201, created.text
    task_id = created.json()["id"]

    manifest = gateway_client.get(f"/v1/dev/worker/tasks/{task_id}/input")
    assert manifest.status_code == 200, manifest.text
    body = manifest.json()
    assert body["taskType"] == "document.ocr"
    assert "INVOICE" in body["prompt"]

    uploaded = gateway_client.post(
        f"/v1/dev/worker/tasks/{task_id}/output",
        json={"resultText": "INVOICE #INV-2026-0847\nTOTAL 99.16"},
    )
    assert uploaded.status_code == 201, uploaded.text

    tasks = gateway_client.get(f"/v1/workspaces/{fixtures.DEV_WORKSPACE_PRIMARY}/tasks")
    assert tasks.status_code == 200
    match = next(item for item in tasks.json()["items"] if item["id"] == task_id)
    assert match["executionStatus"] == "completed"
    assert match["lifecycleStatus"] == "succeeded"
