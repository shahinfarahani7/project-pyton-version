from __future__ import annotations

from unittest.mock import AsyncMock
from uuid import uuid4

import pytest

from edgemint.building_blocks.settings import Settings
from edgemint.routing.errors import RouterServiceError
from edgemint.routing.envelope_registry import envelope_for_task_type
from edgemint.routing.resource_budget import (
    EffectiveResourceBudgets,
    ResourceClassTotals,
    compute_effective_resource_budgets,
    contribution_budget_multiplier_bps,
    resource_class_budget_reasons,
)
from edgemint.routing.resource_reservations import (
    ResourceReservationService,
    reservation_vector_for_task_type,
)
from edgemint.workers.device_capability import (
    BatterySpec,
    DeviceCapabilityReport,
    MemorySpec,
    NetworkSpec,
    PlatformSpec,
    ResourceVector,
    StorageSpec,
    ThermalSpec,
)


def _reference_capability() -> DeviceCapabilityReport:
    return DeviceCapabilityReport(
        platform=PlatformSpec(os="android", abi="arm64-v8a", apiLevel=34, pageSizeKb=16),
        deviceTier="T4",
        regionCode="US",
        runtimeAbi="mediapipe-llm-v1",
        resourceVector=ResourceVector(
            cpuUnits=100,
            memoryBytes=12_884_901_888,
            storageBytes=21_474_836_480,
            acceleratorUnits=0,
            modelSessionUnits=2,
        ),
        runtimeClasses=["mediapipe_llm", "paddle_ocr", "system"],
        storage=StorageSpec(
            availableBytes=21_474_836_480,
            minimumFreeBytes=1_073_741_824,
            maxAiStorageBytes=5_368_709_120,
        ),
        memory=MemorySpec(
            totalRamBytes=12_884_901_888,
            availableBytes=8_589_934_592,
            safetyReserveBytes=536_870_912,
        ),
        thermal=ThermalSpec(state="nominal"),
        battery=BatterySpec(levelBps=8000, charging=True),
        network=NetworkSpec(type="wifi"),
    )


def test_cpu_memory_storage_budgets_are_computed_independently() -> None:
    capability = _reference_capability()
    budgets = compute_effective_resource_budgets(
        capability=capability,
        contribution_multiplier_bps=contribution_budget_multiplier_bps(approved_percent=50),
    )
    assert budgets.cpu_units == 50
    assert budgets.memory_bytes < capability.memory.availableBytes
    assert budgets.storage_bytes <= capability.storage.maxAiStorageBytes
    assert budgets.cpu_units != budgets.memory_bytes


def test_mixed_ocr_then_llm_respects_independent_class_totals() -> None:
    capability = _reference_capability()
    budgets = compute_effective_resource_budgets(
        capability=capability,
        contribution_multiplier_bps=contribution_budget_multiplier_bps(approved_percent=100),
    )
    ocr = reservation_vector_for_task_type("document.ocr")
    llm = reservation_vector_for_task_type("text.summarize")
    assert ocr.cpu_units == envelope_for_task_type("document.ocr").cpu_units  # type: ignore[union-attr]
    assert llm.cpu_units == envelope_for_task_type("text.summarize").cpu_units  # type: ignore[union-attr]

    after_ocr = ResourceClassTotals(
        cpu_units=ocr.cpu_units,
        memory_bytes=ocr.memory_bytes,
        storage_bytes=ocr.storage_bytes,
    )
    assert resource_class_budget_reasons(
        effective=budgets,
        reserved=after_ocr,
        requested=ResourceClassTotals(
            cpu_units=llm.cpu_units,
            memory_bytes=llm.memory_bytes,
            storage_bytes=llm.storage_bytes,
        ),
    ) == []

    saturated_cpu = ResourceClassTotals(
        cpu_units=budgets.cpu_units,
        memory_bytes=0,
        storage_bytes=0,
    )
    assert resource_class_budget_reasons(
        effective=budgets,
        reserved=saturated_cpu,
        requested=ResourceClassTotals(cpu_units=1, memory_bytes=0, storage_bytes=0),
    ) == ["CPU_BUDGET_EXCEEDED"]


def test_memory_budget_can_block_llm_even_when_cpu_has_headroom() -> None:
    capability = _reference_capability()
    budgets = EffectiveResourceBudgets(
        cpu_units=100,
        memory_bytes=1_600_000_000,
        storage_bytes=5_000_000_000,
    )
    llm = reservation_vector_for_task_type("text.summarize")
    reserved = ResourceClassTotals(cpu_units=10, memory_bytes=1_500_000_000, storage_bytes=0)
    reasons = resource_class_budget_reasons(
        effective=budgets,
        reserved=reserved,
        requested=ResourceClassTotals(
            cpu_units=llm.cpu_units,
            memory_bytes=llm.memory_bytes,
            storage_bytes=0,
        ),
    )
    assert reasons == ["MEMORY_BUDGET_EXCEEDED"]


class _ScalarRow:
    def __init__(self, row: dict[str, object] | None) -> None:
        self._row = row

    def mappings(self) -> _ScalarRow:
        return self

    def first(self) -> dict[str, object] | None:
        return self._row


@pytest.mark.asyncio
async def test_reserve_service_blocks_when_per_class_budget_exceeded() -> None:
    service = ResourceReservationService(
        settings=Settings(
            worker_exclusive_group_enforcement_enabled=False,
            worker_per_class_budget_enforcement_enabled=True,
        ),
    )
    capability = _reference_capability()
    ocr = reservation_vector_for_task_type("document.ocr")

    connection = AsyncMock()
    connection.execute = AsyncMock(
        side_effect=[
            _ScalarRow({"capability_snapshot_json": capability.model_dump(mode="json")}),
            _ScalarRow({"contribution_mode_id": "balanced"}),
            _ScalarRow(
                {
                    "cpu_units": capability.resourceVector.cpuUnits,
                    "memory_bytes": 0,
                    "storage_bytes": 0,
                }
            ),
        ]
    )

    with pytest.raises(RouterServiceError) as exc:
        await service.assert_per_class_resource_budget_available(
            connection,
            worker_device_id=uuid4(),
            requested=ocr,
            task_type="document.ocr",
        )

    assert exc.value.code == "CPU_BUDGET_EXCEEDED"
