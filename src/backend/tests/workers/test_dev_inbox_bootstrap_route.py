from __future__ import annotations

import importlib
import sys

import pytest
from fastapi.testclient import TestClient


@pytest.fixture
def development_registry_client(monkeypatch: pytest.MonkeyPatch) -> TestClient:
    monkeypatch.setenv("EDGEMINT_ENVIRONMENT", "development")
    get_settings = importlib.import_module("edgemint.building_blocks.settings").get_settings
    get_settings.cache_clear()

    module_name = "edgemint.services.worker_registry"
    sys.modules.pop(module_name, None)
    worker_registry = importlib.import_module(module_name)
    importlib.reload(worker_registry)
    return TestClient(worker_registry.app)


def test_inbox_bootstrap_route_registered_in_development(
    development_registry_client: TestClient,
) -> None:
    response = development_registry_client.get("/assignments:inboxBootstrap")
    assert response.status_code != 404
    assert response.status_code in {401, 403, 422}


def test_cancelled_dev_assignment_is_removed_from_queue(
    development_registry_client: TestClient,
) -> None:
    created = development_registry_client.post(
        "/internal/dev/assignments",
        json={"taskId": "tsk_cancel_route", "taskType": "text.summarize"},
    )
    assert created.status_code == 201

    cancelled = development_registry_client.delete(
        "/internal/dev/assignments/tsk_cancel_route"
    )
    assert cancelled.status_code == 204

    pending = development_registry_client.get("/internal/dev/assignments")
    assert pending.status_code == 200
    assert all(
        assignment["assignmentId"] != "tsk_cancel_route"
        for assignment in pending.json()["items"]
    )


def test_dev_confirm_stop_route_is_registered(
    development_registry_client: TestClient,
) -> None:
    paths = development_registry_client.app.openapi()["paths"]
    assert "/assignments/{assignment_id}:confirmStop" in paths
