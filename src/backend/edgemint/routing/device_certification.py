from __future__ import annotations

from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.workers.calibration import load_calibration_metrics


async def load_device_concurrency_certified(
    connection: AsyncConnection,
    *,
    worker_device_id: UUID,
) -> bool:
    metrics = await load_calibration_metrics(connection, worker_device_id=worker_device_id)
    if metrics is None:
        return False
    return bool(metrics.concurrencyCertified)


async def load_device_thermal_state(
    connection: AsyncConnection,
    *,
    worker_device_id: UUID,
) -> str | None:
    row = (
        await connection.execute(
            text(
                """
                SELECT thermal_state
                FROM public.worker_heartbeats
                WHERE worker_device_id = :worker_device_id
                ORDER BY observed_at_utc DESC
                LIMIT 1
                """
            ),
            {"worker_device_id": worker_device_id},
        )
    ).mappings().first()
    if row is None:
        return None
    return str(row["thermal_state"])
