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
