"""Persist worker-panel Fibonai points in Postgres.

Points are an integer display credit, not a euro amount and not contribution XP.
"""

from __future__ import annotations

from sqlalchemy import text

from edgemint.building_blocks.database import transaction

POINTS_PER_COMPLETED_TASK = 40


async def credit_completed_task(*, device_public_id: str, task_id: str) -> dict[str, object] | None:
    """Insert one credit for this device and task. Missing devices are ignored."""
    device_public_id = device_public_id.strip()
    task_id = task_id.strip()
    if not device_public_id or not task_id:
        return None
    async with transaction(isolation="READ COMMITTED") as connection:
        found = await connection.execute(
            text("SELECT id FROM public.worker_devices WHERE public_id = :public_id"),
            {"public_id": device_public_id},
        )
        device_row = found.first()
        if device_row is None:
            return None
        await connection.execute(
            text(
                """
                INSERT INTO public.worker_fibonai_credits (worker_device_id, task_id, points)
                VALUES (:device_id, :task_id, :points)
                ON CONFLICT (worker_device_id, task_id) DO NOTHING
                """
            ),
            {
                "device_id": device_row[0],
                "task_id": task_id,
                "points": POINTS_PER_COMPLETED_TASK,
            },
        )
        return await _balance_for_device_id(connection, device_row[0], device_public_id)


async def balance_for_device(device_public_id: str) -> dict[str, object] | None:
    device_public_id = device_public_id.strip()
    if not device_public_id:
        return None
    async with transaction(isolation="READ COMMITTED") as connection:
        found = await connection.execute(
            text("SELECT id FROM public.worker_devices WHERE public_id = :public_id"),
            {"public_id": device_public_id},
        )
        device_row = found.first()
        if device_row is None:
            return None
        return await _balance_for_device_id(connection, device_row[0], device_public_id)


async def _balance_for_device_id(connection, device_id: object, device_public_id: str) -> dict[str, object]:
    totals = await connection.execute(
        text(
            """
            SELECT COALESCE(SUM(points), 0)::int AS points,
                   COUNT(*)::int AS tasks_completed
            FROM public.worker_fibonai_credits
            WHERE worker_device_id = :device_id
            """
        ),
        {"device_id": device_id},
    )
    row = totals.one()
    return {
        "knownDevice": True,
        "deviceId": device_public_id,
        "points": int(row.points),
        "tasksCompleted": int(row.tasks_completed),
        "pointsPerTask": POINTS_PER_COMPLETED_TASK,
    }
