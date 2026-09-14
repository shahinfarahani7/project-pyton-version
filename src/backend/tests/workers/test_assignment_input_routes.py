from __future__ import annotations

import importlib
import sys
from uuid import uuid4

import pytest
from edgemint.building_blocks.settings import Settings
from fastapi.testclient import TestClient


@pytest.fixture
def production_registry_client(monkeypatch: pytest.MonkeyPatch) -> TestClient:
    monkeypatch.setenv("EDGEMINT_ENVIRONMENT", "production")
    monkeypatch.setenv("EDGEMINT_LEASE_CREDENTIAL_ENCRYPTION_KEY", "a" * 44)
    get_settings = importlib.import_module("edgemint.building_blocks.settings").get_settings
    get_settings.cache_clear()

    module_name = "edgemint.services.worker_registry"
    sys.modules.pop(module_name, None)
    worker_registry = importlib.import_module(module_name)
    importlib.reload(worker_registry)

    return TestClient(worker_registry.app)


def test_input_manifest_route_registered_in_production(
    production_registry_client: TestClient,
) -> None:
    assignment_id = str(uuid4())
    response = production_registry_client.get(
        f"/assignments/{assignment_id}/input-manifest",
    )
    assert response.status_code != 404
    assert response.status_code in {401, 403, 422}


def test_output_route_registered_in_production(
    production_registry_client: TestClient,
) -> None:
    assignment_id = str(uuid4())
    response = production_registry_client.post(
        f"/assignments/{assignment_id}/output",
        json={"resultText": "hello"},
    )
    assert response.status_code != 404
    assert response.status_code in {401, 403, 422}
