from __future__ import annotations

import secrets
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.building_blocks.settings import Settings, get_settings
from edgemint.security.tokens import hash_session_token
from edgemint.workers.errors import worker_error


@dataclass(frozen=True, slots=True)
class WorkerSessionContext:
    session_id: UUID
    worker_id: UUID
    worker_public_id: str
    device_id: UUID
    device_public_id: str
    principal_id: UUID
    worker_status: str
    device_status: str
    attestation_status: str
    attestation_expires_at: datetime
    installation_id: str | None


def issue_session_token(*, settings: Settings | None = None) -> tuple[str, bytes, datetime]:
    active = settings or get_settings()
    token = secrets.token_urlsafe(48)
    expires_at = datetime.now(UTC) + timedelta(seconds=active.worker_session_ttl_seconds)
    return token, hash_session_token(token), expires_at


async def persist_worker_session(
    connection: AsyncConnection,
    *,
    worker_device_id: UUID,
    token_hash: bytes,
    expires_at: datetime,
) -> UUID:
    session_id = (
        await connection.execute(
            text(
                """
                INSERT INTO public.worker_sessions(worker_device_id, session_token_hash, expires_at_utc)
                VALUES (:worker_device_id, :session_token_hash, :expires_at_utc)
                RETURNING id
                """
            ),
            {
                "worker_device_id": worker_device_id,
                "session_token_hash": token_hash,
                "expires_at_utc": expires_at,
            },
        )
    ).scalar_one()
    return session_id


async def resolve_worker_session(
    connection: AsyncConnection,
    *,
    access_token: str,
    expected_worker_public_id: str | None = None,
) -> WorkerSessionContext:
    row = (
        await connection.execute(
            text(
                """
                SELECT
                    session.id AS session_id,
                    session.expires_at_utc,
                    device.id AS device_id,
                    device.public_id AS device_public_id,
                    device.status AS device_status,
                    device.attestation_status,
                    device.attestation_expires_at_utc,
                    device.installation_id,
                    worker.id AS worker_id,
                    worker.public_id AS worker_public_id,
                    worker.status AS worker_status,
                    worker.principal_id
                FROM public.worker_sessions AS session
                JOIN public.worker_devices AS device ON device.id = session.worker_device_id
                JOIN public.workers AS worker ON worker.id = device.worker_id
                WHERE session.session_token_hash = :session_token_hash
                LIMIT 1
                """
            ),
            {"session_token_hash": hash_session_token(access_token)},
        )
    ).mappings().first()
    if row is None:
        raise worker_error("AUTH_INVALID_CREDENTIAL")
    now = datetime.now(UTC)
    if row["expires_at_utc"] < now:
        raise worker_error("AUTH_INVALID_CREDENTIAL", detail="session expired")
    if expected_worker_public_id and row["worker_public_id"] != expected_worker_public_id:
        raise worker_error("TENANT_RESOURCE_NOT_FOUND", detail="worker mismatch")
    if row["worker_status"] in {"banned", "quarantined"}:
        raise worker_error("WORKER_QUARANTINED")
    return WorkerSessionContext(
        session_id=UUID(str(row["session_id"])),
        worker_id=UUID(str(row["worker_id"])),
        worker_public_id=str(row["worker_public_id"]),
        device_id=UUID(str(row["device_id"])),
        device_public_id=str(row["device_public_id"]),
        principal_id=UUID(str(row["principal_id"])),
        worker_status=str(row["worker_status"]),
        device_status=str(row["device_status"]),
        attestation_status=str(row["attestation_status"]),
        attestation_expires_at=row["attestation_expires_at_utc"],
        installation_id=str(row["installation_id"]) if row["installation_id"] else None,
    )
