"""Release assignments whose lease elapsed while the worker was gone."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import text

from edgemint.building_blocks.database import transaction

_ACTIVE = frozenset({"leased", "running"})
_LEAVE = frozenset(
    {"completed", "failed", "expired", "revoked", "stale", "cancelled"}
)


def plan_lease_expiry(
    *,
    assignment_status: str,
    lease_expires_at: datetime,
    now: datetime,
) -> str:
    """`expire_and_release` or `leave`. Terminal and unexpired rows stay put."""
    if assignment_status in _LEAVE or assignment_status not in _ACTIVE:
        return "leave"
    if lease_expires_at > now:
        return "leave"
    return "expire_and_release"


async def expire_elapsed_assignment_leases() -> int:
    async with transaction() as connection:
        count = (
            await connection.execute(text("SELECT public.expire_elapsed_assignment_leases()"))
        ).scalar_one()
    return int(count)
