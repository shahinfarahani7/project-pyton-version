from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.workers.device_capability import DeviceCapabilityReport
from edgemint.workers.resource_policy import (
    default_contribution_mode_id,
    load_active_user_resource_policy,
    validate_contribution_mode_id,
)


@dataclass(frozen=True, slots=True)
class ResourceClassTotals:
    cpu_units: int
    memory_bytes: int
    storage_bytes: int


@dataclass(frozen=True, slots=True)
class EffectiveResourceBudgets:
    cpu_units: int
    memory_bytes: int
    storage_bytes: int


def contribution_budget_multiplier_bps(*, approved_percent: int) -> int:
    """Map user-approved contribution percent to an integer budget multiplier (bps).

    Architecture §15/§64: 30% balanced → 3000 bps, 50% performance → 5000 bps.
    """
    if not 1 <= approved_percent <= 100:
        raise ValueError("approved_percent out of range")
    return approved_percent * 100


def contribution_budget_multiplier_bps_for_mode(mode_id: str) -> int:
    mode = validate_contribution_mode_id(mode_id)
    return contribution_budget_multiplier_bps(approved_percent=mode.approvedPercent)


def apply_contribution_budget(*, capacity_units: int, budget_multiplier_bps: int) -> int:
    """Return effective capacity after user contribution cap (integer floor)."""
    if capacity_units < 0:
        raise ValueError("capacity_units must be non-negative")
    if budget_multiplier_bps < 0 or budget_multiplier_bps > 10_000:
        raise ValueError("budget_multiplier_bps out of range")
    return (capacity_units * budget_multiplier_bps) // 10_000


async def load_contribution_budget_multiplier_bps(
    connection: AsyncConnection,
    *,
    worker_id: UUID,
) -> int:
    row = (
        await connection.execute(
            text(
                """
                SELECT contribution_mode_id
                FROM public.worker_preferences
                WHERE worker_id = :worker_id
                """
            ),
            {"worker_id": worker_id},
        )
    ).mappings().first()
    mode_id = str(row["contribution_mode_id"]) if row else default_contribution_mode_id()
    return contribution_budget_multiplier_bps_for_mode(mode_id)


CONTRIBUTION_BUDGET_MULTIPLIERS_BPS: dict[str, int] = {
    "balanced": contribution_budget_multiplier_bps_for_mode("balanced"),
    "performance": contribution_budget_multiplier_bps_for_mode("performance"),
}


def compute_effective_resource_budgets(
    *,
    capability: DeviceCapabilityReport,
    contribution_multiplier_bps: int,
    safety_reserve_percent: int | None = None,
) -> EffectiveResourceBudgets:
    """Architecture §16: CPU, memory, and storage budgets are computed independently."""
    policy = load_active_user_resource_policy()
    reserve_percent = safety_reserve_percent
    if reserve_percent is None:
        reserve_percent = policy.spec.resourcePolicy.safetyReservePercent

    user_cpu_budget = apply_contribution_budget(
        capacity_units=capability.resourceVector.cpuUnits,
        budget_multiplier_bps=contribution_multiplier_bps,
    )
    user_memory_limit = apply_contribution_budget(
        capacity_units=capability.memory.totalRamBytes,
        budget_multiplier_bps=contribution_multiplier_bps,
    )
    memory_safety = max(
        capability.memory.safetyReserveBytes,
        (capability.memory.totalRamBytes * reserve_percent) // 100,
    )
    available_memory_budget = max(0, capability.memory.availableBytes - memory_safety)
    effective_memory = min(user_memory_limit, available_memory_budget)

    storage_free_budget = max(
        0,
        capability.storage.availableBytes - capability.storage.minimumFreeBytes,
    )
    effective_storage = min(capability.storage.maxAiStorageBytes, storage_free_budget)

    return EffectiveResourceBudgets(
        cpu_units=user_cpu_budget,
        memory_bytes=effective_memory,
        storage_bytes=effective_storage,
    )


def resource_class_budget_reasons(
    *,
    effective: EffectiveResourceBudgets,
    reserved: ResourceClassTotals,
    requested: ResourceClassTotals,
) -> list[str]:
    reasons: list[str] = []
    if reserved.cpu_units + requested.cpu_units > effective.cpu_units:
        reasons.append("CPU_BUDGET_EXCEEDED")
    if reserved.memory_bytes + requested.memory_bytes > effective.memory_bytes:
        reasons.append("MEMORY_BUDGET_EXCEEDED")
    if reserved.storage_bytes + requested.storage_bytes > effective.storage_bytes:
        reasons.append("STORAGE_BUDGET_EXCEEDED")
    return reasons


async def load_device_resource_class_totals(
    connection: AsyncConnection,
    *,
    worker_device_id: UUID,
) -> ResourceClassTotals:
    row = (
        await connection.execute(
            text(
                """
                SELECT
                    COALESCE(SUM(cpu_units), 0) AS cpu_units,
                    COALESCE(SUM(memory_bytes), 0) AS memory_bytes,
                    COALESCE(SUM(storage_bytes), 0) AS storage_bytes
                FROM public.worker_resource_reservations
                WHERE worker_device_id = :worker_device_id
                  AND status IN ('reserved', 'active')
                """
            ),
            {"worker_device_id": worker_device_id},
        )
    ).mappings().first()
    if row is None:
        return ResourceClassTotals(cpu_units=0, memory_bytes=0, storage_bytes=0)
    return ResourceClassTotals(
        cpu_units=int(row["cpu_units"]),
        memory_bytes=int(row["memory_bytes"]),
        storage_bytes=int(row["storage_bytes"]),
    )


async def load_worker_device_capability(
    connection: AsyncConnection,
    *,
    worker_device_id: UUID,
) -> DeviceCapabilityReport | None:
    row = (
        await connection.execute(
            text(
                """
                SELECT capability_snapshot_json
                FROM public.worker_devices
                WHERE id = :worker_device_id
                """
            ),
            {"worker_device_id": worker_device_id},
        )
    ).mappings().first()
    if row is None or row["capability_snapshot_json"] is None:
        heartbeat = (
            await connection.execute(
                text(
                    """
                    SELECT capability_snapshot_json
                    FROM public.worker_heartbeats
                    WHERE worker_device_id = :worker_device_id
                      AND capability_snapshot_json IS NOT NULL
                    ORDER BY received_at_utc DESC, sequence_number DESC
                    LIMIT 1
                    """
                ),
                {"worker_device_id": worker_device_id},
            )
        ).mappings().first()
        if heartbeat is None or heartbeat["capability_snapshot_json"] is None:
            return None
        return DeviceCapabilityReport.model_validate(dict(heartbeat["capability_snapshot_json"]))
    return DeviceCapabilityReport.model_validate(dict(row["capability_snapshot_json"]))


async def load_contribution_budget_multiplier_bps_for_device(
    connection: AsyncConnection,
    *,
    worker_device_id: UUID,
) -> int:
    row = (
        await connection.execute(
            text(
                """
                SELECT preference.contribution_mode_id
                FROM public.worker_devices AS device
                JOIN public.worker_preferences AS preference
                  ON preference.worker_id = device.worker_id
                WHERE device.id = :worker_device_id
                """
            ),
            {"worker_device_id": worker_device_id},
        )
    ).mappings().first()
    mode_id = str(row["contribution_mode_id"]) if row else default_contribution_mode_id()
    return contribution_budget_multiplier_bps_for_mode(mode_id)
