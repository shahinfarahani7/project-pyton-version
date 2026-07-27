from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection


@dataclass(frozen=True, slots=True)
class InboxRecord:
    consumer_name: str
    event_id: UUID
    event_type: str
    payload_sha256: str


async def insert_inbox_event(connection: AsyncConnection, record: InboxRecord) -> None:
    await connection.execute(
        text(
            """
            INSERT INTO public.inbox_events(
                consumer_name, event_id, event_type, payload_sha256
            )
            VALUES (:consumer_name, :event_id, :event_type, :payload_sha256)
            ON CONFLICT (consumer_name, event_id) DO NOTHING
            """
        ),
        {
            "consumer_name": record.consumer_name,
            "event_id": record.event_id,
            "event_type": record.event_type,
            "payload_sha256": record.payload_sha256,
        },
    )


async def record_inbox_before_ack(
    connection: AsyncConnection,
    *,
    inbox: InboxRecord,
    delivery_id: UUID,
    sequence: int,
    principal_id: UUID,
) -> None:
    """Persist inbox side effects before acknowledging durable WebSocket delivery."""
    await insert_inbox_event(connection, inbox)
    await connection.execute(
        text("SELECT eventing.acknowledge_delivery(:delivery_id, :sequence, :principal_id)"),
        {
            "delivery_id": delivery_id,
            "sequence": sequence,
            "principal_id": principal_id,
        },
    )
