from __future__ import annotations

import json
import os

import pytest
from edgemint.building_blocks.settings import Settings
from edgemint.dev import fixtures
from edgemint.results.text_summarize_constraints import (
    DEFAULT_TEXT_SUMMARIZE_PORTAL_OPTIONS,
    SummarizeConstraintsError,
    parse_summarize_constraints,
)
from edgemint.services import api_gateway
from fastapi.testclient import TestClient

pytestmark = pytest.mark.filterwarnings("ignore::jwt.InsecureKeyLengthWarning")
TEST_SIGNING_SECRET = "x" * 32


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


def _login(gateway_client: TestClient) -> None:
    response = gateway_client.post(
        "/auth/sessions",
        json={
            "principalId": str(fixtures.DEV_PRINCIPAL_ID),
            "workspaceId": str(fixtures.DEV_WORKSPACE_PRIMARY),
            "permissions": ["customer.tasks:read", "customer.tasks:write"],
        },
    )
    assert response.status_code == 200, response.text


def _valid_summarize_envelope(*, key_point_count: int = 5) -> dict:
    points = [
        "Order A184 arrived late.",
        "Tracking showed five minutes away for an hour.",
        "Order A219 had an unauthorized substitution.",
        "Order A237 has a pending authorization for $64.80.",
        "Support promised a $12 refund within five business days.",
    ]
    if key_point_count < len(points):
        points = points[:key_point_count]
    elif key_point_count > len(points):
        points.extend(f"Extra point {index}" for index in range(len(points), key_point_count))
    return {
        "schemaVersion": "1",
        "taskId": "tsk_test",
        "status": "SUCCEEDED",
        "output": {
            "data": {
                "summary": "Customer reported delivery, tracking, product, billing, and support issues.",
                "keyPoints": points,
                "mainComplaint": "Unauthorized dietary substitution.",
                "suggestedImprovement": "Audit substitution approvals.",
                "missingOrUnclear": ["Whether pending authorization becomes a charge."],
            }
        },
        "metrics": {"llmMs": 100},
    }


requires_postgres = pytest.mark.skipif(
    not os.environ.get("EDGEMINT_DATABASE_URL"),
    reason="PostgreSQL not available",
)


@requires_postgres
def test_portal_create_stores_summarize_options_in_worker_manifest(
    gateway_client: TestClient,
) -> None:
    _login(gateway_client)
    created = gateway_client.post(
        f"/v1/workspaces/{fixtures.DEV_WORKSPACE_PRIMARY}/tasks",
        json={
            "taskType": "text.summarize",
            "inputText": "Customer feedback about delivery and billing.",
            "instructions": "Analyze the customer feedback using only the provided content.",
            "summarizeOptions": DEFAULT_TEXT_SUMMARIZE_PORTAL_OPTIONS,
        },
    )
    assert created.status_code == 201, created.text
    task_id = created.json()["id"]

    manifest = gateway_client.get(f"/v1/dev/worker/tasks/{task_id}/input")
    assert manifest.status_code == 200, manifest.text
    manifest_body = manifest.json()
    summarize = manifest_body["options"]["summarize"]
    assert summarize["schemaVersion"] == "1"
    assert summarize["keyPointCount"] == 5
    assert summarize["maxSummaryWords"] == 80
    assert "delivery" in summarize["coverageAxes"]


@requires_postgres
def test_rejected_output_does_not_mark_portal_task_succeeded(
    gateway_client: TestClient,
) -> None:
    _login(gateway_client)
    created = gateway_client.post(
        f"/v1/workspaces/{fixtures.DEV_WORKSPACE_PRIMARY}/tasks",
        json={
            "taskType": "text.summarize",
            "inputText": "Customer feedback about delivery and billing.",
            "instructions": "Return five key points.",
            "summarizeOptions": {"schemaVersion": "1", "keyPointCount": 5},
        },
    )
    assert created.status_code == 201, created.text
    task_id = created.json()["id"]

    invalid = gateway_client.post(
        f"/v1/dev/worker/tasks/{task_id}/output",
        json={
            "resultText": "bad summary",
            "metrics": {
                "structuredResultJson": json.dumps(_valid_summarize_envelope(key_point_count=3)),
            },
        },
    )
    assert invalid.status_code == 422

    task = gateway_client.get(
        f"/v1/workspaces/{fixtures.DEV_WORKSPACE_PRIMARY}/tasks/{task_id}"
    )
    assert task.status_code == 200, task.text
    body = task.json()
    assert body["lifecycleStatus"] == "failed"
    assert body["executionStatus"] == "failed"
    assert body.get("failureReasonCode") == "SUMMARIZE_OUTPUT_REJECTED"
    assert "keyPoints count" in str(body.get("failureReason", ""))

    repeat = gateway_client.post(
        f"/v1/dev/worker/tasks/{task_id}/output",
        json={
            "resultText": "bad summary again",
            "metrics": {
                "structuredResultJson": json.dumps(_valid_summarize_envelope(key_point_count=3)),
            },
        },
    )
    assert repeat.status_code == 422
    task_after_repeat = gateway_client.get(
        f"/v1/workspaces/{fixtures.DEV_WORKSPACE_PRIMARY}/tasks/{task_id}"
    ).json()
    assert task_after_repeat["lifecycleStatus"] == "failed"
    assert task_after_repeat.get("failureReasonCode") == "SUMMARIZE_OUTPUT_REJECTED"


@requires_postgres
def test_validation_uses_manifest_constraints_not_worker_metrics(
    gateway_client: TestClient,
) -> None:
    _login(gateway_client)
    created = gateway_client.post(
        f"/v1/workspaces/{fixtures.DEV_WORKSPACE_PRIMARY}/tasks",
        json={
            "taskType": "text.summarize",
            "inputText": "Sample feedback.",
            "summarizeOptions": {"schemaVersion": "1", "keyPointCount": 5},
        },
    )
    assert created.status_code == 201, created.text
    task_id = created.json()["id"]

    envelope = _valid_summarize_envelope(key_point_count=3)
    envelope["metrics"] = {
        "llmMs": 100,
        "summarize": {"schemaVersion": "1", "keyPointCount": 3},
    }
    response = gateway_client.post(
        f"/v1/dev/worker/tasks/{task_id}/output",
        json={
            "resultText": envelope["output"]["data"]["summary"],
            "metrics": {"structuredResultJson": json.dumps(envelope)},
        },
    )
    assert response.status_code == 422
    detail = response.json()
    assert "keyPoints count" in str(detail)


@requires_postgres
def test_valid_output_marks_portal_task_succeeded(gateway_client: TestClient) -> None:
    _login(gateway_client)
    created = gateway_client.post(
        f"/v1/workspaces/{fixtures.DEV_WORKSPACE_PRIMARY}/tasks",
        json={
            "taskType": "text.summarize",
            "inputText": "Sample feedback.",
            "summarizeOptions": {"schemaVersion": "1", "keyPointCount": 5},
        },
    )
    assert created.status_code == 201, created.text
    task_id = created.json()["id"]
    envelope = _valid_summarize_envelope()

    response = gateway_client.post(
        f"/v1/dev/worker/tasks/{task_id}/output",
        json={
            "resultText": envelope["output"]["data"]["summary"],
            "metrics": {"structuredResultJson": json.dumps(envelope)},
        },
    )
    assert response.status_code == 201

    task = gateway_client.get(
        f"/v1/workspaces/{fixtures.DEV_WORKSPACE_PRIMARY}/tasks/{task_id}"
    ).json()
    assert task["lifecycleStatus"] == "succeeded"
    assert task["executionStatus"] == "completed"


@requires_postgres
def test_generic_portal_task_manifest_has_no_summarize_options(
    gateway_client: TestClient,
) -> None:
    _login(gateway_client)
    created = gateway_client.post(
        f"/v1/workspaces/{fixtures.DEV_WORKSPACE_PRIMARY}/tasks",
        json={
            "taskType": "text.summarize",
            "inputText": "Generic feedback without structured options.",
            "instructions": "Summarize briefly.",
        },
    )
    assert created.status_code == 201, created.text
    task_id = created.json()["id"]

    manifest = gateway_client.get(f"/v1/dev/worker/tasks/{task_id}/input")
    assert manifest.status_code == 200, manifest.text
    options = manifest.json()["options"]
    assert "summarize" not in options


@requires_postgres
def test_late_invalid_upload_does_not_downgrade_accepted_result(
    gateway_client: TestClient,
) -> None:
    _login(gateway_client)
    created = gateway_client.post(
        f"/v1/workspaces/{fixtures.DEV_WORKSPACE_PRIMARY}/tasks",
        json={
            "taskType": "text.summarize",
            "inputText": "Sample feedback.",
            "summarizeOptions": {"schemaVersion": "1", "keyPointCount": 5},
        },
    )
    assert created.status_code == 201, created.text
    task_id = created.json()["id"]
    envelope = _valid_summarize_envelope()

    accepted = gateway_client.post(
        f"/v1/dev/worker/tasks/{task_id}/output",
        json={
            "resultText": envelope["output"]["data"]["summary"],
            "metrics": {"structuredResultJson": json.dumps(envelope)},
        },
    )
    assert accepted.status_code == 201

    invalid = gateway_client.post(
        f"/v1/dev/worker/tasks/{task_id}/output",
        json={
            "resultText": "bad summary",
            "metrics": {
                "structuredResultJson": json.dumps(_valid_summarize_envelope(key_point_count=3)),
            },
        },
    )
    assert invalid.status_code == 422

    task = gateway_client.get(
        f"/v1/workspaces/{fixtures.DEV_WORKSPACE_PRIMARY}/tasks/{task_id}"
    ).json()
    assert task["lifecycleStatus"] == "succeeded"
    assert task["executionStatus"] == "completed"


def test_portal_summarize_options_validation_rejects_invalid_rule() -> None:
    from fastapi import HTTPException

    from edgemint.dev.portal_api import _parse_summarize_options

    with pytest.raises(HTTPException) as exc:
        _parse_summarize_options(
            {"schemaVersion": "1", "billingRules": ["unknown_rule_id"]}
        )
    assert exc.value.status_code == 422


def test_parse_summarize_constraints_rejects_unknown_billing_rule() -> None:
    with pytest.raises(SummarizeConstraintsError, match="Unknown billingRules id"):
        parse_summarize_constraints(
            {
                "schemaVersion": "1",
                "billingRules": ["unknown_rule_id"],
            }
        )
