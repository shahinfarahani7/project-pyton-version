from __future__ import annotations

import os
from uuid import UUID

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
def test_dev_portal_routes_require_session(gateway_client: TestClient) -> None:
    response = gateway_client.get("/v1/workspaces")
    assert response.status_code == 401


@requires_postgres
def test_dev_portal_lists_workspace_data(gateway_client: TestClient) -> None:
    login = gateway_client.post(
        "/auth/sessions",
        json={
            "principalId": str(fixtures.DEV_PRINCIPAL_ID),
            "workspaceId": str(fixtures.DEV_WORKSPACE_PRIMARY),
            "permissions": ["customer.tasks:read", "customer.billing:read"],
        },
    )
    assert login.status_code == 200, login.text

    workspaces = gateway_client.get("/v1/workspaces")
    assert workspaces.status_code == 200
    assert len(workspaces.json()["items"]) == 2

    tasks = gateway_client.get(f"/v1/workspaces/{fixtures.DEV_WORKSPACE_PRIMARY}/tasks")
    assert tasks.status_code == 200
    assert len(tasks.json()["items"]) >= 3

    billing = gateway_client.get(f"/v1/workspaces/{fixtures.DEV_WORKSPACE_PRIMARY}/credit-balance")
    assert billing.status_code == 200
    assert billing.json()["status"] == "ready"

    wrong_workspace = gateway_client.get(f"/v1/workspaces/{fixtures.DEV_WORKSPACE_STAGING}/tasks")
    assert wrong_workspace.status_code == 403


@requires_postgres
def test_dev_portal_creates_task_with_custom_text(gateway_client: TestClient) -> None:
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
        json={"taskType": "text.summarize", "inputText": "Customer paragraph about EdgeMint testing."},
    )
    assert created.status_code == 201, created.text
    body = created.json()
    assert body["taskType"] == "text.summarize"
    assert body["inputLabel"] == "Pasted text"

    manifest = gateway_client.get(f"/v1/dev/worker/tasks/{body['id']}/input")
    assert manifest.status_code == 200, manifest.text
    manifest_body = manifest.json()
    assert manifest_body["customInput"] is True
    assert "Customer paragraph about EdgeMint testing." in manifest_body["prompt"]


@requires_postgres
def test_dev_portal_creates_task(gateway_client: TestClient) -> None:
    login = gateway_client.post(
        "/auth/sessions",
        json={
            "principalId": str(fixtures.DEV_PRINCIPAL_ID),
            "workspaceId": str(fixtures.DEV_WORKSPACE_PRIMARY),
            "permissions": ["customer.tasks:read", "customer.tasks:write"],
        },
    )
    assert login.status_code == 200, login.text

    before = gateway_client.get(f"/v1/workspaces/{fixtures.DEV_WORKSPACE_PRIMARY}/tasks")
    assert before.status_code == 200
    initial_count = len(before.json()["items"])

    created = gateway_client.post(
        f"/v1/workspaces/{fixtures.DEV_WORKSPACE_PRIMARY}/tasks",
        json={"taskType": "document.ocr"},
    )
    assert created.status_code == 201, created.text
    body = created.json()
    assert body["taskType"] == "document.ocr"
    assert body["lifecycleStatus"] == "queued"
    assert body["executionStatus"] == "pending"
    assert body["assignmentId"] == body["id"]
    assert body["createdAt"]
    assert body["updatedAt"]

    after = gateway_client.get(f"/v1/workspaces/{fixtures.DEV_WORKSPACE_PRIMARY}/tasks")
    assert after.status_code == 200
    assert len(after.json()["items"]) == initial_count + 1


@requires_postgres
def test_dev_portal_lists_task_types(gateway_client: TestClient) -> None:
    login = gateway_client.post(
        "/auth/sessions",
        json={
            "principalId": str(fixtures.DEV_PRINCIPAL_ID),
            "workspaceId": str(fixtures.DEV_WORKSPACE_PRIMARY),
            "permissions": ["customer.tasks:read"],
        },
    )
    assert login.status_code == 200, login.text

    catalog = gateway_client.get("/v1/task-types")
    assert catalog.status_code == 200
    body = catalog.json()
    assert body["total"] >= 50
    assert any(item["value"] == "ocr.receipt" for item in body["items"])

    filtered = gateway_client.get("/v1/task-types", params={"q": "nsfw"})
    assert filtered.status_code == 200
    assert filtered.json()["total"] >= 1


@requires_postgres
def test_dev_portal_rejects_unknown_task_type(gateway_client: TestClient) -> None:
    login = gateway_client.post(
        "/auth/sessions",
        json={
            "principalId": str(fixtures.DEV_PRINCIPAL_ID),
            "workspaceId": str(fixtures.DEV_WORKSPACE_PRIMARY),
            "permissions": ["customer.tasks:write"],
        },
    )
    assert login.status_code == 200, login.text

    created = gateway_client.post(
        f"/v1/workspaces/{fixtures.DEV_WORKSPACE_PRIMARY}/tasks",
        json={"taskType": "unknown.task"},
    )
    assert created.status_code == 422
    assert created.json()["detail"] == "UNSUPPORTED_TASK_TYPE"


@requires_postgres
def test_dev_portal_task_responses_include_task_type_meta(gateway_client: TestClient) -> None:
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
        json={"taskType": "ocr.receipt"},
    )
    assert created.status_code == 201, created.text
    body = created.json()
    assert body["taskType"] == "ocr.receipt"
    assert body["taskTypeLabel"] == "OCR receipt"
    assert body["taskTypeMeta"]["pipelineFamily"] == "document.ocr"

    listed = gateway_client.get(f"/v1/workspaces/{fixtures.DEV_WORKSPACE_PRIMARY}/tasks")
    assert listed.status_code == 200
    matched = next(item for item in listed.json()["items"] if item["id"] == body["id"])
    assert matched["taskTypeLabel"] == "OCR receipt"
    assert matched["taskTypeMeta"]["value"] == "ocr.receipt"
