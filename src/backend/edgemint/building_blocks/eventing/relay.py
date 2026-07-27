from __future__ import annotations

import hashlib
import json
import secrets
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.building_blocks.database import transaction
from edgemint.building_blocks.ids import public_id


def hash_resume_token(token: str) -> bytes:
    return hashlib.sha256(token.encode("utf-8")).digest()


def new_resume_token() -> tuple[str, bytes, datetime]:
    token = secrets.token_urlsafe(32)
    return token, hash_resume_token(token), datetime.now(UTC) + timedelta(days=30)


async def open_connection(
    connection: AsyncConnection,
    *,
    principal_id: UUID,
    workspace_id: UUID | None,
    client_id: str,
    client_version: str,
    relay_instance_id: str,
    owner_lease_seconds: int,
) -> tuple[UUID, str]:
    resume_token, resume_hash, resume_expiry = new_resume_token()
    connection_id = (
        await connection.execute(
            text(
                """
                SELECT eventing.open_websocket_connection(
                    :public_id, :principal_id, :workspace_id, :client_id, :client_version,
                    :resume_hash, :resume_expiry, :relay_instance_id, :owner_lease_seconds
                )
                """
            ),
            {
                "public_id": public_id("wsc"),
                "principal_id": principal_id,
                "workspace_id": workspace_id,
                "client_id": client_id,
                "client_version": client_version,
                "resume_hash": resume_hash,
                "resume_expiry": resume_expiry,
                "relay_instance_id": relay_instance_id,
                "owner_lease_seconds": owner_lease_seconds,
            },
        )
    ).scalar_one()
    return connection_id, resume_token


async def resume_connection(
    connection: AsyncConnection,
    *,
    principal_id: UUID,
    workspace_id: UUID | None,
    client_id: str,
    client_version: str,
    resume_token: str,
    relay_instance_id: str,
    owner_lease_seconds: int,
) -> tuple[UUID, str]:
    resume_hash = hash_resume_token(resume_token)
    new_token, new_hash, new_expiry = new_resume_token()
    row = (
        await connection.execute(
            text(
                """
                SELECT id
                FROM public.websocket_connections
                WHERE resume_token_hash = :resume_hash
                  AND principal_id = :principal_id
                  AND workspace_id IS NOT DISTINCT FROM :workspace_id
                  AND client_id = :client_id
                  AND client_version = :client_version
                  AND resume_expires_at_utc > CURRENT_TIMESTAMP
                FOR UPDATE
                """
            ),
            {
                "resume_hash": resume_hash,
                "principal_id": principal_id,
                "workspace_id": workspace_id,
                "client_id": client_id,
                "client_version": client_version,
            },
        )
    ).one_or_none()
    if row is None:
        raise ValueError("RESUME_TOKEN_INVALID")

    connection_id = row.id
    await connection.execute(
        text(
            """
            UPDATE public.websocket_connections
            SET status = 'connected',
                relay_instance_id = :relay_instance_id,
                resume_token_hash = :new_resume_hash,
                resume_expires_at_utc = :new_resume_expiry,
                owner_lease_expires_at_utc = CURRENT_TIMESTAMP + make_interval(secs => :owner_lease_seconds),
                connected_at_utc = CURRENT_TIMESTAMP,
                last_heartbeat_at_utc = CURRENT_TIMESTAMP,
                disconnected_at_utc = NULL
            WHERE id = :connection_id
            """
        ),
        {
            "connection_id": connection_id,
            "relay_instance_id": relay_instance_id,
            "new_resume_hash": new_hash,
            "new_resume_expiry": new_expiry,
            "owner_lease_seconds": owner_lease_seconds,
        },
    )
    await connection.execute(
        text(
            """
            UPDATE public.websocket_subscriptions
            SET status = 'active'
            WHERE connection_id = :connection_id
              AND status = 'expired'
            """
        ),
        {"connection_id": connection_id},
    )
    return connection_id, new_token


async def create_subscription(
    connection: AsyncConnection,
    *,
    connection_id: UUID,
    principal_id: UUID,
    workspace_id: UUID | None,
    event_types: list[str],
) -> UUID:
    return (
        await connection.execute(
            text(
                """
                SELECT eventing.create_websocket_subscription(
                    :public_id, :connection_id, :principal_id, :workspace_id, CAST(:event_types AS jsonb)
                )
                """
            ),
            {
                "public_id": public_id("sub"),
                "connection_id": connection_id,
                "principal_id": principal_id,
                "workspace_id": workspace_id,
                "event_types": json.dumps(event_types),
            },
        )
    ).scalar_one()


async def claim_deliveries(
    *,
    connection_id: UUID,
    relay_instance_id: str,
    lease_seconds: int,
    max_in_flight: int,
) -> list[dict[str, Any]]:
    async with transaction(isolation="READ COMMITTED") as connection:
        rows = (
            await connection.execute(
                text(
                    """
                    SELECT delivery_id, delivery_sequence, cloud_event_json
                    FROM eventing.claim_websocket_deliveries(
                        :relay_instance_id, :connection_id, 64, :lease_seconds, :max_in_flight
                    )
                    """
                ),
                {
                    "relay_instance_id": relay_instance_id,
                    "connection_id": connection_id,
                    "lease_seconds": lease_seconds,
                    "max_in_flight": max_in_flight,
                },
            )
        ).mappings().all()
        return [dict(row) for row in rows]
