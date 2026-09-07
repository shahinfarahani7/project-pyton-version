from __future__ import annotations

import asyncio
from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock
from uuid import uuid4

import pytest

from edgemint.building_blocks.settings import Settings
from edgemint.routing.errors import RouterServiceError
from edgemint.routing.exclusive_groups import (
    can_reserve_exclusive_group,
    exclusive_group_enforcement_reasons,
)
from edgemint.routing.resource_reservations import ResourceReservationService


class _CountRows:
    def __init__(self, rows: list[dict[str, object]]) -> None:
        self._rows = rows

    def mappings(self) -> _CountRows:
        return self

    def __iter__(self):
        return iter(self._rows)


def _mock_connection(count_result: _CountRows) -> AsyncMock:
    connection = AsyncMock()

    async def _execute(statement, params=None):
        sql = str(statement)
        if "worker_calibration_profiles" in sql or "worker_heartbeats" in sql:

            class _Empty:
                def mappings(self) -> _Empty:
                    return self

                def first(self) -> None:
                    return None

            return _Empty()
        return count_result

    connection.execute = AsyncMock(side_effect=_execute)
    return connection


def test_second_llm_reservation_blocked_when_group_saturated() -> None:
    reasons = exclusive_group_enforcement_reasons(
        requested_group="llm_inference",
        active_counts={"llm_inference": 1},
    )
    assert reasons == ["EXCLUSIVE_GROUP_SATURATED"]
    assert can_reserve_exclusive_group(
        requested_group="llm_inference",
        active_counts={"llm_inference": 1},
    ) is False


def test_ocr_blocked_while_llm_active_by_cross_group_rule() -> None:
    reasons = exclusive_group_enforcement_reasons(
        requested_group="ocr_inference",
        active_counts={"llm_inference": 1},
    )
    assert reasons == ["EXCLUSIVE_GROUP_CROSS_BLOCKED"]


def test_light_network_io_allowed_during_llm() -> None:
    assert can_reserve_exclusive_group(
        requested_group="network_io",
        active_counts={"llm_inference": 1},
    ) is True


@pytest.mark.asyncio
async def test_reserve_service_blocks_second_heavy_task() -> None:
    service = ResourceReservationService(
        settings=Settings(worker_exclusive_group_enforcement_enabled=True),
    )
    count_result = _CountRows(
        [{"exclusive_group": "llm_inference", "reservation_count": 1}],
    )
    connection = _mock_connection(count_result)

    with pytest.raises(RouterServiceError) as exc:
        await service.assert_exclusive_group_available(
            connection,
            worker_device_id=uuid4(),
            exclusive_group="llm_inference",
        )

    assert exc.value.code == "EXCLUSIVE_GROUP_SATURATED"


@pytest.mark.asyncio
async def test_reserve_service_blocks_ocr_when_llm_active() -> None:
    service = ResourceReservationService(
        settings=Settings(worker_exclusive_group_enforcement_enabled=True),
    )
    count_result = _CountRows(
        [{"exclusive_group": "llm_inference", "reservation_count": 1}],
    )
    connection = _mock_connection(count_result)

    with pytest.raises(RouterServiceError) as exc:
        await service.assert_exclusive_group_available(
            connection,
            worker_device_id=uuid4(),
            exclusive_group="ocr_inference",
        )

    assert exc.value.code == "EXCLUSIVE_GROUP_CROSS_BLOCKED"


@pytest.mark.asyncio
async def test_concurrent_reserve_checks_use_same_device_counts() -> None:
    service = ResourceReservationService(
        settings=Settings(worker_exclusive_group_enforcement_enabled=True),
    )
    count_result = _CountRows(
        [{"exclusive_group": "llm_inference", "reservation_count": 1}],
    )
    connection = _mock_connection(count_result)
    device_id = uuid4()

    results = await asyncio.gather(
        service.assert_exclusive_group_available(
            connection,
            worker_device_id=device_id,
            exclusive_group="llm_inference",
        ),
        service.assert_exclusive_group_available(
            connection,
            worker_device_id=device_id,
            exclusive_group="llm_inference",
        ),
        return_exceptions=True,
    )

    assert all(isinstance(item, RouterServiceError) for item in results)
    assert all(item.code == "EXCLUSIVE_GROUP_SATURATED" for item in results)  # type: ignore[union-attr]


@pytest.mark.asyncio
async def test_reserve_for_assignment_calls_enforcement_before_sql_create() -> None:
    service = ResourceReservationService(
        settings=Settings(
            worker_exclusive_group_enforcement_enabled=True,
            worker_resource_reservations_enabled=True,
        ),
    )
    count_result = _CountRows(
        [{"exclusive_group": "llm_inference", "reservation_count": 1}],
    )
    connection = _mock_connection(count_result)

    with pytest.raises(RouterServiceError) as exc:
        await service.reserve_for_assignment(
            connection,
            workspace_id=uuid4(),
            assignment_id=uuid4(),
            worker_device_id=uuid4(),
            task_revision_id=uuid4(),
            task_type="text.summarize",
            fence_token=2,
            expires_at_utc=datetime.now(UTC) + timedelta(minutes=5),
        )

    assert exc.value.code == "EXCLUSIVE_GROUP_SATURATED"
    assert connection.execute.await_count >= 1
