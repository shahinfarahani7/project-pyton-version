from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.workers.errors import worker_error


@dataclass(frozen=True, slots=True)
class AssignmentDeliveryRecord:
    delivery_id: UUID
    assignment_id: UUID
    fence_token: int
    delivery_channel: str
    acked: bool


class AssignmentDeliveryInboxService:
    """Server-side durable assignment delivery inbox (v2 §7, §39, A03)."""

    async def record_poll_delivery(
        self,
        connection: AsyncConnection,
        *,
        workspace_id: UUID,
        assignment_id: UUID,
        worker_device_id: UUID,
        fence_token: int,
    ) -> UUID:
        delivery_id = (
            await connection.execute(
                text(
                    """
                    SELECT public.record_worker_assignment_delivery(
                        :workspace_id, :assignment_id, :worker_device_id,
                        :fence_token, 'poll'
                    )
                    """
                ),
                {
                    "workspace_id": workspace_id,
                    "assignment_id": assignment_id,
                    "worker_device_id": worker_device_id,
                    "fence_token": fence_token,
                },
            )
        ).scalar_one()
        return UUID(str(delivery_id))

    async def acknowledge_delivery(
        self,
        connection: AsyncConnection,
        *,
        assignment_id: UUID,
        worker_device_id: UUID,
        fence_token: int,
        ack_sequence: int = 1,
    ) -> bool:
        if ack_sequence < 1:
            raise worker_error("INPUT_SCHEMA_INVALID", detail="ack sequence must be >= 1")
        acknowledged = (
            await connection.execute(
                text(
                    """
                    SELECT public.acknowledge_worker_assignment_delivery(
                        :assignment_id, :worker_device_id, :fence_token, :ack_sequence
                    )
                    """
                ),
                {
                    "assignment_id": assignment_id,
                    "worker_device_id": worker_device_id,
                    "fence_token": fence_token,
                    "ack_sequence": ack_sequence,
                },
            )
        ).scalar_one()
        return bool(acknowledged)

    async def bootstrap_for_device(
        self,
        connection: AsyncConnection,
        *,
        worker_device_id: UUID,
        limit: int = 32,
    ) -> list[AssignmentDeliveryRecord]:
        if limit < 1 or limit > 256:
            raise worker_error("INPUT_SCHEMA_INVALID", detail="bootstrap limit out of range")
        rows = (
            await connection.execute(
                text(
                    """
                    SELECT
                        delivery.id AS delivery_id,
                        delivery.assignment_id,
                        delivery.fence_token,
                        delivery.delivery_channel,
                        (delivery.ack_received_at_utc IS NOT NULL) AS acked
                    FROM public.worker_assignment_deliveries AS delivery
                    JOIN public.assignments AS assignment
                      ON assignment.id = delivery.assignment_id
                     AND assignment.workspace_id = delivery.workspace_id
                    WHERE delivery.worker_device_id = :worker_device_id
                      AND assignment.status IN ('leased', 'running')
                    ORDER BY delivery.inbox_recorded_at_utc DESC
                    LIMIT :limit
                    """
                ),
                {"worker_device_id": worker_device_id, "limit": limit},
            )
        ).mappings()
        return [
            AssignmentDeliveryRecord(
                delivery_id=UUID(str(row["delivery_id"])),
                assignment_id=UUID(str(row["assignment_id"])),
                fence_token=int(row["fence_token"]),
                delivery_channel=str(row["delivery_channel"]),
                acked=bool(row["acked"]),
            )
            for row in rows
        ]
