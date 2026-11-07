"""Persist worker-panel Fibonai points in Postgres.

Points are an integer display credit, not a euro amount and not contribution XP.
"""

from __future__ import annotations

from collections.abc import Iterable
from datetime import UTC, datetime

from sqlalchemy import text

from edgemint.building_blocks.database import transaction

RECENT_CREDIT_WINDOW_DAYS = 8


def points_per_accepted_task() -> int:
    """FibonAI atomic units paid to the worker who completes one accepted task."""
    from edgemint.economy.fibonai_token import quote_accepted_task

    return quote_accepted_task().worker_reward_atomic


async def credit_completed_task(
    *,
    device_public_id: str,
    task_id: str,
    points: int,
) -> dict[str, object] | None:
    """Insert one credit for this device and task. Missing devices are ignored."""
    device_public_id = device_public_id.strip()
    task_id = task_id.strip()
    if not device_public_id or not task_id or type(points) is not int or points <= 0:
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
                "points": points,
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
    recent = await connection.execute(
        text(
            """
            SELECT points, created_at_utc
            FROM public.worker_fibonai_credits
            WHERE worker_device_id = :device_id
              AND created_at_utc >= CURRENT_TIMESTAMP - make_interval(days => :days)
            ORDER BY created_at_utc ASC
            """
        ),
        {"device_id": device_id, "days": RECENT_CREDIT_WINDOW_DAYS},
    )
    return {
        "knownDevice": True,
        "deviceId": device_public_id,
        "points": int(row.points),
        "tasksCompleted": int(row.tasks_completed),
        "pointsPerTask": points_per_accepted_task(),
        "recentCredits": recent_credit_records(recent),
    }


def recent_credit_records(rows: Iterable[object]) -> list[dict[str, object]]:
    """Serialize credit rows as `{points, creditedAtUtc}` for the worker chart."""
    records: list[dict[str, object]] = []
    for row in rows:
        points = getattr(row, "points", None)
        created_at = getattr(row, "created_at_utc", None)
        if points is None or created_at is None:
            if isinstance(row, tuple) and len(row) >= 2:
                points, created_at = row[0], row[1]
            else:
                continue
        if not isinstance(created_at, datetime):
            continue
        point_value = int(points)
        if point_value <= 0:
            continue
        if created_at.tzinfo is None:
            created_at = created_at.replace(tzinfo=UTC)
        else:
            created_at = created_at.astimezone(UTC)
        records.append(
            {
                "points": point_value,
                "creditedAtUtc": created_at.isoformat().replace("+00:00", "Z"),
            }
        )
    return records
