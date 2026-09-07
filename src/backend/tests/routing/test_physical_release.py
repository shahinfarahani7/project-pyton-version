from __future__ import annotations

from unittest.mock import AsyncMock
from uuid import uuid4

import pytest

from edgemint.routing.errors import RouterServiceError
from edgemint.routing.physical_release import (
    UNCERTAIN_PHYSICAL_STATES,
    PhysicalReleaseService,
    PhysicalReleaseState,
)


class _ScalarResult:
    def __init__(self, value: object) -> None:
        self._value = value

    def scalar_one(self) -> object:
        return self._value

    def scalar_one_or_none(self) -> object | None:
        return self._value


def test_uncertain_physical_states_exclude_released() -> None:
    assert PhysicalReleaseState.RELEASED not in UNCERTAIN_PHYSICAL_STATES
    assert PhysicalReleaseState.STOP_REQUESTED in UNCERTAIN_PHYSICAL_STATES


@pytest.mark.asyncio
async def test_confirm_stop_requires_proof() -> None:
    service = PhysicalReleaseService()
    with pytest.raises(RouterServiceError) as exc_info:
        await service.confirm_stop_for_assignment(
            AsyncMock(),
            assignment_id=uuid4(),
            fence_token=3,
            proof="   ",
        )
    assert exc_info.value.code == "INPUT_SCHEMA_INVALID"


@pytest.mark.asyncio
async def test_confirm_stop_returns_committed_flag() -> None:
    service = PhysicalReleaseService()
    connection = AsyncMock()
    assignment_id = uuid4()
    reservation_id = uuid4()
    connection.execute = AsyncMock(
        side_effect=[
            _ScalarResult(True),
            _ScalarResult(reservation_id),
            _ScalarResult("released"),
        ]
    )

    commit = await service.confirm_stop_for_assignment(
        connection,
        assignment_id=assignment_id,
        fence_token=4,
        proof="assignment|4|cleanup|stop_confirmed",
    )

    assert commit.committed is True
    assert commit.physical_release_state is PhysicalReleaseState.RELEASED


@pytest.mark.asyncio
async def test_device_has_uncertain_physical_hold() -> None:
    service = PhysicalReleaseService()
    connection = AsyncMock()
    connection.execute = AsyncMock(return_value=_ScalarResult(2))

    assert await service.device_has_uncertain_physical_hold(
        connection,
        worker_device_id=uuid4(),
        exclusive_group="mediapipe_llm",
    )
