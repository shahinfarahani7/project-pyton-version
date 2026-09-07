from __future__ import annotations

import asyncio
from unittest.mock import AsyncMock
from uuid import uuid4

import pytest

from edgemint.routing.resource_reservations import (
    ResourceReservationService,
    reservation_vector_for_task_type,
)


class _ScalarResult:
    def __init__(self, value: object) -> None:
        self._value = value

    def scalar_one(self) -> object:
        return self._value

    def scalar_one_or_none(self) -> object:
        return self._value


def test_text_summarize_envelope_maps_to_reservation_vector() -> None:
    vector = reservation_vector_for_task_type("text.summarize")
    assert vector.cpu_units > 0
    assert vector.model_session_units > 0


@pytest.mark.asyncio
async def test_release_for_assignment_is_idempotent() -> None:
    service = ResourceReservationService()
    connection = AsyncMock()
    assignment_id = uuid4()
    connection.execute.return_value = _ScalarResult(True)

    first = await service.release_for_assignment(connection, assignment_id=assignment_id)
    second = await service.release_for_assignment(connection, assignment_id=assignment_id)

    assert first is True
    assert second is True
    assert connection.execute.await_count == 2


@pytest.mark.asyncio
async def test_concurrent_release_calls_both_succeed() -> None:
    service = ResourceReservationService()
    connection = AsyncMock()
    assignment_id = uuid4()
    connection.execute.return_value = _ScalarResult(True)

    first, second = await asyncio.gather(
        service.release_for_assignment(connection, assignment_id=assignment_id),
        service.release_for_assignment(connection, assignment_id=assignment_id),
    )

    assert first is True
    assert second is True


@pytest.mark.asyncio
async def test_activate_returns_false_when_no_reserved_row() -> None:
    service = ResourceReservationService()
    connection = AsyncMock()
    connection.execute.return_value = _ScalarResult(None)

    activated = await service.activate_for_assignment(
        connection,
        assignment_id=uuid4(),
        fence_token=3,
    )

    assert activated is False
