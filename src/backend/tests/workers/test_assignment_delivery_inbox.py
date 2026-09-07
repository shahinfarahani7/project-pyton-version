from __future__ import annotations

from unittest.mock import AsyncMock
from uuid import uuid4

import pytest

from edgemint.workers.assignment_delivery_inbox import AssignmentDeliveryInboxService
from edgemint.workers.errors import WorkerServiceError


class _ScalarResult:
    def __init__(self, value: object) -> None:
        self._value = value

    def scalar_one(self) -> object:
        return self._value

    def scalar_one_or_none(self) -> object | None:
        return self._value


class _MappingsResult:
    def __init__(self, rows: list[dict[str, object]]) -> None:
        self._rows = rows

    def mappings(self) -> _MappingsResult:
        return self

    def __iter__(self):
        return iter(self._rows)


@pytest.mark.asyncio
async def test_record_poll_delivery_returns_uuid() -> None:
    service = AssignmentDeliveryInboxService()
    connection = AsyncMock()
    delivery_id = uuid4()
    connection.execute = AsyncMock(return_value=_ScalarResult(delivery_id))

    recorded = await service.record_poll_delivery(
        connection,
        workspace_id=uuid4(),
        assignment_id=uuid4(),
        worker_device_id=uuid4(),
        fence_token=3,
    )

    assert recorded == delivery_id


@pytest.mark.asyncio
async def test_acknowledge_delivery_is_idempotent() -> None:
    service = AssignmentDeliveryInboxService()
    connection = AsyncMock()
    connection.execute = AsyncMock(return_value=_ScalarResult(True))

    acknowledged = await service.acknowledge_delivery(
        connection,
        assignment_id=uuid4(),
        worker_device_id=uuid4(),
        fence_token=5,
    )

    assert acknowledged is True


@pytest.mark.asyncio
async def test_acknowledge_delivery_rejects_invalid_sequence() -> None:
    service = AssignmentDeliveryInboxService()
    with pytest.raises(WorkerServiceError) as exc_info:
        await service.acknowledge_delivery(
            AsyncMock(),
            assignment_id=uuid4(),
            worker_device_id=uuid4(),
            fence_token=5,
            ack_sequence=0,
        )
    assert exc_info.value.code == "INPUT_SCHEMA_INVALID"


@pytest.mark.asyncio
async def test_bootstrap_for_device_maps_rows() -> None:
    service = AssignmentDeliveryInboxService()
    connection = AsyncMock()
    assignment_id = uuid4()
    delivery_id = uuid4()
    connection.execute = AsyncMock(
        return_value=_MappingsResult(
            [
                {
                    "delivery_id": delivery_id,
                    "assignment_id": assignment_id,
                    "fence_token": 9,
                    "delivery_channel": "poll",
                    "acked": False,
                }
            ]
        )
    )

    records = await service.bootstrap_for_device(connection, worker_device_id=uuid4())

    assert len(records) == 1
    assert records[0].delivery_id == delivery_id
    assert records[0].fence_token == 9
    assert records[0].acked is False
