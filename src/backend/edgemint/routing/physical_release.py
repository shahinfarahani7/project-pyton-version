from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.routing.errors import router_error


class PhysicalReleaseState(StrEnum):
    HELD = "held"
    STOP_REQUESTED = "stop_requested"
    UNKNOWN = "unknown"
    RELEASED = "released"


UNCERTAIN_PHYSICAL_STATES = frozenset(
    {
        PhysicalReleaseState.HELD,
        PhysicalReleaseState.STOP_REQUESTED,
        PhysicalReleaseState.UNKNOWN,
    }
)


@dataclass(frozen=True, slots=True)
class PhysicalReleaseCommit:
    reservation_id: UUID | None
    assignment_id: UUID
    physical_release_state: PhysicalReleaseState | None
    committed: bool


class PhysicalReleaseService:
    """Stop requested vs stop confirmed for resource reservations (v2 §19, §47)."""

    async def request_stop_for_assignment(
        self,
        connection: AsyncConnection,
        *,
        assignment_id: UUID,
        fence_token: int,
        reason: str = "logical_release",
    ) -> bool:
        reservation_id = await self._latest_reservation_id(connection, assignment_id=assignment_id)
        if reservation_id is None:
            return False
        requested = (
            await connection.execute(
                text(
                    """
                    SELECT public.request_worker_physical_stop(
                        :reservation_id, :fence_token, :reason
                    )
                    """
                ),
                {
                    "reservation_id": reservation_id,
                    "fence_token": fence_token,
                    "reason": reason,
                },
            )
        ).scalar_one()
        return bool(requested)

    async def confirm_stop_for_assignment(
        self,
        connection: AsyncConnection,
        *,
        assignment_id: UUID,
        fence_token: int,
        proof: str,
        reason: str = "worker_stop_confirmed",
    ) -> PhysicalReleaseCommit:
        if not proof.strip():
            raise router_error("INPUT_SCHEMA_INVALID", detail="physical release proof required")
        committed = (
            await connection.execute(
                text(
                    """
                    SELECT public.confirm_worker_physical_release_by_assignment(
                        :assignment_id, :fence_token, :proof, :reason
                    )
                    """
                ),
                {
                    "assignment_id": assignment_id,
                    "fence_token": fence_token,
                    "proof": proof,
                    "reason": reason,
                },
            )
        ).scalar_one()
        reservation_id = await self._latest_reservation_id(connection, assignment_id=assignment_id)
        state = (
            await self.get_state_for_assignment(connection, assignment_id=assignment_id)
            if reservation_id is not None
            else None
        )
        return PhysicalReleaseCommit(
            reservation_id=reservation_id,
            assignment_id=assignment_id,
            physical_release_state=state,
            committed=bool(committed),
        )

    async def get_state_for_assignment(
        self,
        connection: AsyncConnection,
        *,
        assignment_id: UUID,
    ) -> PhysicalReleaseState | None:
        row = (
            await connection.execute(
                text(
                    """
                    SELECT physical_release_state
                    FROM public.worker_resource_reservations
                    WHERE assignment_id = :assignment_id
                    ORDER BY reserved_at_utc DESC
                    LIMIT 1
                    """
                ),
                {"assignment_id": assignment_id},
            )
        ).scalar_one_or_none()
        return PhysicalReleaseState(str(row)) if row is not None else None

    async def device_has_uncertain_physical_hold(
        self,
        connection: AsyncConnection,
        *,
        worker_device_id: UUID,
        exclusive_group: str,
    ) -> bool:
        if not exclusive_group:
            return False
        count = (
            await connection.execute(
                text(
                    """
                    SELECT COUNT(*)::int
                    FROM public.worker_resource_reservations
                    WHERE worker_device_id = :worker_device_id
                      AND exclusive_group = :exclusive_group
                      AND physical_release_state IN ('held', 'stop_requested', 'unknown')
                      AND (
                        status IN ('reserved', 'active')
                        OR status IN ('released', 'expired', 'revoked')
                      )
                    """
                ),
                {
                    "worker_device_id": worker_device_id,
                    "exclusive_group": exclusive_group,
                },
            )
        ).scalar_one()
        return int(count) > 0

    @staticmethod
    async def _latest_reservation_id(
        connection: AsyncConnection,
        *,
        assignment_id: UUID,
    ) -> UUID | None:
        reservation_id = (
            await connection.execute(
                text(
                    """
                    SELECT id
                    FROM public.worker_resource_reservations
                    WHERE assignment_id = :assignment_id
                    ORDER BY reserved_at_utc DESC
                    LIMIT 1
                    """
                ),
                {"assignment_id": assignment_id},
            )
        ).scalar_one_or_none()
        return UUID(str(reservation_id)) if reservation_id is not None else None
