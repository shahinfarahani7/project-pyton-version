from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection


@dataclass(frozen=True, slots=True)
class OutboxEvent:
    event_type: str
    aggregate_type: str
    aggregate_id: str
    aggregate_sequence: int
    cloud_event: dict[str, Any]
    workspace_id: UUID | None = None


async def enqueue_outbox_event(connection: AsyncConnection, event: OutboxEvent) -> UUID:
    """Insert an outbox row in the same transaction as domain state changes."""
    event_id = (
        await connection.execute(
            text(
                """
                INSERT INTO public.outbox_events(
                    workspace_id, event_type, aggregate_type, aggregate_id,
                    aggregate_sequence, cloud_event_json, status
                )
                VALUES (
                    :workspace_id, :event_type, :aggregate_type, :aggregate_id,
                    :aggregate_sequence, CAST(:cloud_event_json AS jsonb), 'pending'
                )
                RETURNING id
                """
            ),
            {
                "workspace_id": event.workspace_id,
                "event_type": event.event_type,
                "aggregate_type": event.aggregate_type,
                "aggregate_id": event.aggregate_id,
                "aggregate_sequence": event.aggregate_sequence,
                "cloud_event_json": json.dumps(event.cloud_event, separators=(",", ":"), sort_keys=True),
            },
        )
    ).scalar_one()
    return event_id


def cloud_event_payload_sha256(cloud_event: dict[str, Any]) -> str:
    payload = json.dumps(cloud_event, separators=(",", ":"), sort_keys=True).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()
