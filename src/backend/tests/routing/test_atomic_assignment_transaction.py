from __future__ import annotations

import base64
from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock
from uuid import uuid4

import pytest

from edgemint.building_blocks.settings import Settings
from edgemint.routing.atomic_assignment import ATOMIC_ASSIGNMENT_TRANSACTION_STEPS, AtomicAssignmentTransaction
from edgemint.routing.errors import RouterServiceError
from edgemint.routing.service import RouterService


class _MappingResult:
    def __init__(self, row: dict[str, object] | None) -> None:
        self._row = row

    def mappings(self) -> _MappingResult:
        return self

    def first(self) -> dict[str, object] | None:
        return self._row


class _InsertResult:
    pass


def test_atomic_assignment_transaction_steps_match_section_20() -> None:
    assert ATOMIC_ASSIGNMENT_TRANSACTION_STEPS[0] == "lock_task_attempt"
    assert ATOMIC_ASSIGNMENT_TRANSACTION_STEPS[-1] == "commit"
    assert "create_resource_reservation" in ATOMIC_ASSIGNMENT_TRANSACTION_STEPS
    assert "create_assignment" in ATOMIC_ASSIGNMENT_TRANSACTION_STEPS
    assert "create_outbox_event" in ATOMIC_ASSIGNMENT_TRANSACTION_STEPS
    reservation_index = ATOMIC_ASSIGNMENT_TRANSACTION_STEPS.index("create_resource_reservation")
    assignment_index = ATOMIC_ASSIGNMENT_TRANSACTION_STEPS.index("create_assignment")
    assert reservation_index < assignment_index


@pytest.mark.asyncio
async def test_acquire_with_reservation_propagates_sql_failure_before_credentials() -> None:
    reservations = AsyncMock()
    reservations.assert_exclusive_group_available = AsyncMock()
    reservations.assert_per_class_resource_budget_available = AsyncMock()
    service = AtomicAssignmentTransaction(resource_reservations=reservations)
    connection = AsyncMock()
    connection.execute.side_effect = RouterServiceError(
        code="WORKER_NOT_ELIGIBLE",
        status=409,
        title="Worker not eligible",
    )

    with pytest.raises(RouterServiceError):
        await service.acquire_with_reservation(
            connection,
            task_attempt_id=uuid4(),
            worker_id=uuid4(),
            worker_device_id=uuid4(),
            router_instance_id="router-test",
            lease_token="lease-token",
            lease_token_hash=b"hash",
            lease_seconds=300,
            delivery_seconds=30,
            auto_start_grace_seconds=60,
            heartbeat_max_age_seconds=120,
            min_trust_bps=7000,
            task_type="text.summarize",
        )

    assert connection.execute.await_count == 1


@pytest.mark.asyncio
async def test_acquire_with_reservation_returns_reservation_id_and_persists_credentials() -> None:
    key = b"k" * 32
    settings = Settings(
        environment="test",
        lease_credential_encryption_key=base64.urlsafe_b64encode(key).decode("ascii"),
    )
    reservations = AsyncMock()
    reservations.assert_exclusive_group_available = AsyncMock()
    reservations.assert_per_class_resource_budget_available = AsyncMock()
    service = AtomicAssignmentTransaction(settings=settings, resource_reservations=reservations)
    connection = AsyncMock()
    assignment_id = uuid4()
    reservation_id = uuid4()
    worker_device_id = uuid4()
    connection.execute.side_effect = [
        _MappingResult(
            {
                "assignment_id": assignment_id,
                "fence_token": 7,
                "lease_expires_at_utc": datetime.now(UTC) + timedelta(minutes=5),
                "reservation_id": reservation_id,
            }
        ),
        _InsertResult(),
    ]

    body = await service.acquire_with_reservation(
        connection,
        task_attempt_id=uuid4(),
        worker_id=uuid4(),
        worker_device_id=worker_device_id,
        router_instance_id="router-test",
        lease_token="lease-token",
        lease_token_hash=b"hash",
        lease_seconds=300,
        delivery_seconds=30,
        auto_start_grace_seconds=60,
        heartbeat_max_age_seconds=120,
        min_trust_bps=7000,
        task_type="text.summarize",
    )

    assert body["assignmentId"] == str(assignment_id)
    assert body["reservationId"] == str(reservation_id)
    assert body["fenceToken"] == 7
    credential_params = connection.execute.await_args_list[1].args[1]
    assert credential_params["assignment_id"] == assignment_id
    assert credential_params["worker_device_id"] == worker_device_id


@pytest.mark.asyncio
async def test_router_uses_atomic_path_when_reservations_enabled() -> None:
    key = b"k" * 32
    settings = Settings(
        environment="test",
        lease_credential_encryption_key=base64.urlsafe_b64encode(key).decode("ascii"),
        worker_resource_reservations_enabled=True,
    )
    atomic = AsyncMock()
    atomic.load_task_type_for_attempt = AsyncMock(return_value="text.summarize")
    assignment_id = uuid4()
    reservation_id = uuid4()
    atomic.acquire_with_reservation = AsyncMock(
        return_value={
            "assignmentId": str(assignment_id),
            "reservationId": str(reservation_id),
            "fenceToken": 2,
            "leaseToken": "lease-token",
            "leaseExpiresAt": datetime.now(UTC) + timedelta(minutes=5),
        }
    )
    router = RouterService(settings=settings, atomic_assignment=atomic)
    connection = AsyncMock()
    worker_device_id = uuid4()

    body = await router.acquire_assignment_lease(
        connection,
        task_attempt_id=uuid4(),
        worker_id=uuid4(),
        worker_device_id=worker_device_id,
        router_instance_id="router-test",
    )

    atomic.acquire_with_reservation.assert_awaited_once()
    assert body["reservationId"] == str(reservation_id)
    assert body["assignmentMode"] == router.policy.assignment_mode
