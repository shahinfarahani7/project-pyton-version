from __future__ import annotations

import base64
from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock
from uuid import uuid4

import pytest

from edgemint.building_blocks.settings import Settings
from edgemint.routing.errors import RouterServiceError
from edgemint.routing.service import RouterService


def _candidate(worker_id: str, worker_device_id: str | None = None) -> dict[str, object]:
    return {
        "workerId": worker_id,
        "workerDeviceId": worker_device_id or str(uuid4()),
        "input": {
            "featuresBps": {
                "modelLocality": 10000,
                "trust": 10000,
                "predictedLatency": 10000,
                "batteryCharging": 10000,
                "network": 10000,
                "regionalCompliance": 10000,
                "priceEfficiency": 10000,
                "reliability": 10000,
            },
            "heartbeatAgeSeconds": 1,
            "batteryPercent": 100,
            "thermalState": "nominal",
            "attested": True,
            "consentCurrent": True,
            "modelDigestMatch": True,
            "modelAvailable": True,
            "runtimeAbiMatch": True,
            "regionAllowed": True,
            "networkPolicyAllowed": True,
            "available": True,
            "workerId": worker_id,
            "calibrationFactorBps": 10_000,
        },
    }


@pytest.mark.asyncio
async def test_scheduler_stack_assigns_highest_ranked_eligible_worker() -> None:
    key = b"k" * 32
    settings = Settings(
        environment="test",
        lease_credential_encryption_key=base64.urlsafe_b64encode(key).decode("ascii"),
        worker_resource_reservations_enabled=True,
    )
    audit = AsyncMock()
    audit_id = uuid4()
    audit.record_decision = AsyncMock(return_value=audit_id)
    atomic = AsyncMock()
    atomic.load_task_type_for_attempt = AsyncMock(return_value="text.summarize")
    assignment_id = uuid4()
    atomic.acquire_with_reservation = AsyncMock(
        return_value={
            "assignmentId": str(assignment_id),
            "reservationId": str(uuid4()),
            "fenceToken": 1,
            "leaseToken": "lease-token",
            "leaseExpiresAt": datetime.now(UTC) + timedelta(minutes=5),
        }
    )
    router = RouterService(settings=settings, atomic_assignment=atomic, routing_audit=audit)
    connection = AsyncMock()
    worker_a = str(uuid4())
    worker_b = str(uuid4())
    candidates = [
        _candidate(worker_a),
        {
            **_candidate(worker_b),
            "input": {
                **_candidate(worker_b)["input"],  # type: ignore[index]
                "featuresBps": {
                    **_candidate(worker_b)["input"]["featuresBps"],  # type: ignore[index]
                    "modelLocality": 8500,
                },
            },
        },
    ]

    body = await router.assign_attempt_with_scheduler_stack(
        connection,
        task_attempt_id=uuid4(),
        task_id="tsk_scheduler",
        router_epoch=5,
        router_instance_id="router-test",
        candidates=candidates,
    )

    assert body["workerId"] == worker_a
    assert body["auditId"] == str(audit_id)
    assert body["schedulerTrace"]["selectedWorkerId"] == worker_a
    atomic.acquire_with_reservation.assert_awaited_once()


@pytest.mark.asyncio
async def test_scheduler_stack_tries_next_worker_on_transient_failure() -> None:
    key = b"k" * 32
    settings = Settings(
        environment="test",
        lease_credential_encryption_key=base64.urlsafe_b64encode(key).decode("ascii"),
        worker_resource_reservations_enabled=True,
    )
    audit = AsyncMock()
    audit.record_decision = AsyncMock(return_value=uuid4())
    atomic = AsyncMock()
    atomic.load_task_type_for_attempt = AsyncMock(return_value="text.summarize")
    winner_id = uuid4()
    atomic.acquire_with_reservation = AsyncMock(
        side_effect=[
            RouterServiceError(code="WORKER_NOT_ELIGIBLE", status=409, title="not eligible"),
            {
                "assignmentId": str(uuid4()),
                "reservationId": str(uuid4()),
                "fenceToken": 2,
                "leaseToken": "lease-token",
                "leaseExpiresAt": datetime.now(UTC) + timedelta(minutes=5),
            },
        ]
    )
    router = RouterService(settings=settings, atomic_assignment=atomic, routing_audit=audit)
    connection = AsyncMock()
    candidates = [
        _candidate(str(uuid4())),
        {**_candidate(str(winner_id)), "input": {**_candidate(str(winner_id))["input"], "featuresBps": {**_candidate(str(winner_id))["input"]["featuresBps"], "modelLocality": 8500}}},  # type: ignore[index]
    ]

    body = await router.assign_attempt_with_scheduler_stack(
        connection,
        task_attempt_id=uuid4(),
        task_id="tsk_retry_worker",
        router_epoch=1,
        router_instance_id="router-test",
        candidates=candidates,
    )

    assert body["workerId"] == str(winner_id)
    assert atomic.acquire_with_reservation.await_count == 2


@pytest.mark.asyncio
async def test_scheduler_stack_returns_cloud_fallback_when_exhausted() -> None:
    audit = AsyncMock()
    audit.record_decision = AsyncMock(return_value=uuid4())
    router = RouterService(routing_audit=audit)
    router.acquire_assignment_lease = AsyncMock(  # type: ignore[method-assign]
        side_effect=RouterServiceError(code="WORKER_NOT_ELIGIBLE", status=409, title="not eligible")
    )
    connection = AsyncMock()
    candidates = [_candidate(str(uuid4()))]

    body = await router.assign_attempt_with_scheduler_stack(
        connection,
        task_attempt_id=uuid4(),
        task_id="tsk_cloud",
        router_epoch=1,
        router_instance_id="router-test",
        candidates=candidates,
        edge_wait_seconds=120,
    )

    assert body["assignmentMode"] == "cloud_fallback"
    assert body["cloudFallback"]["permitted"] is True
    assert body["cloudFallback"]["reason"] == "edge_wait_exceeded"


def test_reassignment_budget_blocks_scheduler_stack_before_ranking() -> None:
    router = RouterService()
    with pytest.raises(RouterServiceError) as exc:
        router.check_reassignment_budget(prior_assignments=router.policy.max_worker_reassignments + 1)
    assert exc.value.code == "NO_CAPACITY"


@pytest.mark.asyncio
async def test_reassignment_budget_enforced_in_scheduler_stack() -> None:
    router = RouterService()
    connection = AsyncMock()
    with pytest.raises(RouterServiceError) as exc:
        await router.assign_attempt_with_scheduler_stack(
            connection,
            task_attempt_id=uuid4(),
            task_id="tsk_budget",
            router_epoch=1,
            router_instance_id="router-test",
            candidates=[_candidate(str(uuid4()))],
            prior_assignments=router.policy.max_worker_reassignments + 1,
        )
    assert exc.value.code == "NO_CAPACITY"
