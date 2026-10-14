from __future__ import annotations

import importlib
import sys
from contextlib import asynccontextmanager
from types import SimpleNamespace
from typing import Any
from uuid import UUID

import pytest
from fastapi.testclient import TestClient

from tests.contribution.test_contribution_xp import DEVICE, WORKER, MemoryRepository, _run

VALID_TEST_TOKEN = "valid-worker-token"  # noqa: S105 - fixture value, not a credential


@pytest.fixture
def registry(monkeypatch: pytest.MonkeyPatch) -> Any:
    monkeypatch.setenv("EDGEMINT_ENVIRONMENT", "development")
    importlib.import_module("edgemint.building_blocks.settings").get_settings.cache_clear()
    module_name = "edgemint.services.worker_registry"
    sys.modules.pop(module_name, None)
    module = importlib.import_module(module_name)
    importlib.reload(module)

    repository = MemoryRepository()

    @asynccontextmanager
    async def fake_transaction(**_: Any) -> Any:
        yield object()

    async def fake_session(_connection: Any, *, access_token: str) -> Any:
        if access_token != VALID_TEST_TOKEN:
            from edgemint.workers.errors import worker_error

            raise worker_error("AUTH_INVALID_CREDENTIAL")
        return SimpleNamespace(worker_id=WORKER, device_id=DEVICE)

    monkeypatch.setattr(module, "transaction", fake_transaction)
    monkeypatch.setattr(module, "resolve_worker_session", fake_session)
    monkeypatch.setattr(module, "SqlContributionRepository", lambda _connection: repository)
    module.test_repository = repository
    return module


def _headers(key: str = "idem-contribution-0001") -> dict[str, str]:
    return {"Authorization": "Bearer valid-worker-token", "Idempotency-Key": key}


def test_sync_scores_accepted_runs_once_and_returns_contract_shape(registry: Any) -> None:
    registry.test_repository.runs.append(_run(minutes=2.5))
    client = TestClient(registry.app)

    first = client.post("/worker-contribution:sync", headers=_headers())
    second = client.post("/worker-contribution:sync", headers=_headers("idem-contribution-0002"))

    assert first.status_code == 200
    body = second.json()
    assert body["totalCentiXp"] == 1_500
    assert body["totalXp"] == "15.00"
    assert body["level"] == "bronze"
    assert body["verifiedTaskCount"] == 1
    assert body["acceptedProcessingMs"] == 150_000
    assert body["boostPurchase"] == {
        "enabled": False,
        "blockedReason": "BOOST_PRICE_NOT_CONFIGURED",
        "priceTokenMinorUnits": None,
        "durationHours": 24,
        "taskQuota": 50,
    }
    assert len(registry.test_repository.award_rows) == 1


def test_sync_requires_worker_session(registry: Any) -> None:
    client = TestClient(registry.app)
    response = client.post(
        "/worker-contribution:sync",
        headers={"Authorization": "Bearer wrong", "Idempotency-Key": "idem-contribution-0001"},
    )
    assert response.status_code == 401


def test_boost_purchase_returns_problem_and_activates_nothing(registry: Any) -> None:
    client = TestClient(registry.app)
    response = client.post("/worker-contribution/boosts", headers=_headers())
    assert response.status_code == 409
    assert response.headers["content-type"].startswith("application/problem+json")
    problem = response.json()
    assert problem["code"] == "BOOST_PRICE_NOT_CONFIGURED"
    assert problem["traceId"]
    assert registry.test_repository.boost_rows == {}


def test_boost_purchase_requires_idempotency_key(registry: Any) -> None:
    client = TestClient(registry.app)
    response = client.post(
        "/worker-contribution/boosts", headers={"Authorization": "Bearer valid-worker-token"}
    )
    assert response.status_code == 422
    assert UUID(str(DEVICE))
