"""Persist API keys in api_credentials with the same transaction as audit and outbox."""

from __future__ import annotations

import json
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.building_blocks.eventing.transactional_outbox import OutboxEvent, enqueue_outbox_event
from edgemint.building_blocks.ids import public_id
from edgemint.files.idempotency import begin_idempotent_command, complete_idempotent_command
from edgemint.security.api_key_directory import (
    ApiKeyDirectory,
    ApiKeyError,
    StoredApiKey,
)
from edgemint.security.tokens import write_audit_event

_ADMIN_ROLE = "workspace_admin"


async def create_api_key(
    connection: AsyncConnection,
    keys: ApiKeyDirectory,
    *,
    workspace_id: UUID,
    principal_id: UUID,
    name: str,
    scopes: list[str],
    expires_at: datetime | None,
    allowed_cidrs: list[str],
    idempotency_key: str,
) -> dict[str, Any]:
    await _require_workspace_admin(connection, workspace_id, principal_id)
    await hydrate(connection, keys, workspace_id)
    payload = {
        "name": name.strip(),
        "scopes": sorted(set(scopes)),
        "expiresAt": None if expires_at is None else expires_at.astimezone(UTC).isoformat(),
        "allowedCidrs": allowed_cidrs,
    }
    scope = f"createApiKey:{principal_id}:{workspace_id}"
    replay = await begin_idempotent_command(
        connection,
        workspace_id=workspace_id,
        scope=scope,
        idempotency_key=idempotency_key,
        payload=payload,
    )
    if replay is not None:
        if replay.status_code == 409:
            raise ApiKeyError("IDEMPOTENCY_CONFLICT", 409)
        return replay.body
    issued = keys.issue_new(
        workspace_id=workspace_id,
        name=name,
        scopes=scopes,
        expires_at=expires_at,
        allowed_cidrs=allowed_cidrs,
    )
    try:
        await _insert_credential(connection, issued.record)
        await _audit(connection, principal_id, "api_key.created", issued.record)
        await _outbox(connection, "api_key.created", issued.record)
        await complete_idempotent_command(
            connection,
            workspace_id=workspace_id,
            scope=scope,
            idempotency_key=idempotency_key,
            status_code=201,
            body=issued.body,
        )
    except Exception:
        keys.forget_key(issued.record.public_id)
        raise
    keys._record_change(
        action="api_key.created",
        event_type="api_key.created",
        record=issued.record,
        principal_id=principal_id,
    )
    return issued.body


async def rotate_api_key(
    connection: AsyncConnection,
    keys: ApiKeyDirectory,
    *,
    workspace_id: UUID,
    principal_id: UUID,
    key_id: str,
    idempotency_key: str,
) -> dict[str, Any]:
    await _require_workspace_admin(connection, workspace_id, principal_id)
    await hydrate(connection, keys, workspace_id)
    payload = {"apiKeyId": key_id}
    scope = f"rotateApiKey:{principal_id}:{workspace_id}"
    replay = await begin_idempotent_command(
        connection,
        workspace_id=workspace_id,
        scope=scope,
        idempotency_key=idempotency_key,
        payload=payload,
    )
    if replay is not None:
        if replay.status_code == 409:
            raise ApiKeyError("IDEMPOTENCY_CONFLICT", 409)
        return replay.body
    memory_key = f"durable-rotate-{idempotency_key}"
    try:
        body = keys.rotate(
            workspace_id=workspace_id,
            principal_id=principal_id,
            key_id=key_id,
            idempotency_key=memory_key,
        )
        record = keys._require_active(workspace_id, key_id)
        await _update_credential(connection, record)
        await _audit(connection, principal_id, "api_key.rotated", record)
        await _outbox(connection, "api_key.rotated", record)
        await complete_idempotent_command(
            connection,
            workspace_id=workspace_id,
            scope=scope,
            idempotency_key=idempotency_key,
            status_code=200,
            body=body,
        )
    except ApiKeyError:
        raise
    except Exception:
        keys.forget_receipt(workspace_id, scope, memory_key)
        raise
    return body


async def revoke_api_key(
    connection: AsyncConnection,
    keys: ApiKeyDirectory,
    *,
    workspace_id: UUID,
    principal_id: UUID,
    key_id: str,
    idempotency_key: str,
) -> dict[str, Any]:
    await _require_workspace_admin(connection, workspace_id, principal_id)
    await hydrate(connection, keys, workspace_id)
    payload = {"apiKeyId": key_id}
    scope = f"revokeApiKey:{principal_id}:{workspace_id}"
    replay = await begin_idempotent_command(
        connection,
        workspace_id=workspace_id,
        scope=scope,
        idempotency_key=idempotency_key,
        payload=payload,
    )
    if replay is not None:
        if replay.status_code == 409:
            raise ApiKeyError("IDEMPOTENCY_CONFLICT", 409)
        return replay.body
    memory_key = f"durable-revoke-{idempotency_key}"
    try:
        body = keys.revoke(
            workspace_id=workspace_id,
            principal_id=principal_id,
            key_id=key_id,
            idempotency_key=memory_key,
        )
        record = keys._find(workspace_id, key_id)
        if record is None:
            raise ApiKeyError("API_KEY_NOT_FOUND", 404)
        await connection.execute(
            text(
                """
                UPDATE public.api_credentials
                SET revoked_at_utc = CURRENT_TIMESTAMP
                WHERE workspace_id = :workspace_id
                  AND public_id = :public_id
                  AND revoked_at_utc IS NULL
                """
            ),
            {"workspace_id": workspace_id, "public_id": key_id},
        )
        await _audit(connection, principal_id, "api_key.revoked", record)
        await _outbox(connection, "api_key.revoked", record)
        await complete_idempotent_command(
            connection,
            workspace_id=workspace_id,
            scope=scope,
            idempotency_key=idempotency_key,
            status_code=200,
            body=body,
        )
    except ApiKeyError:
        raise
    except Exception:
        keys.forget_receipt(workspace_id, scope, memory_key)
        raise
    return body


async def hydrate(connection: AsyncConnection, keys: ApiKeyDirectory, workspace_id: UUID) -> None:
    rows = (
        await connection.execute(
            text(
                """
                SELECT id, public_id, secret_hash, permissions_json, expires_at_utc,
                       revoked_at_utc, created_at_utc
                FROM public.api_credentials
                WHERE workspace_id = :workspace_id
                """
            ),
            {"workspace_id": workspace_id},
        )
    ).mappings()
    loaded: list[StoredApiKey] = []
    for row in rows:
        parsed = _metadata(row["permissions_json"])
        if parsed is None:
            continue
        created_at = _as_utc(row["created_at_utc"])
        loaded.append(
            StoredApiKey(
                public_id=str(row["public_id"]),
                internal_id=row["id"],
                workspace_id=workspace_id,
                name=str(parsed["name"]),
                prefix=str(parsed["prefix"]),
                secret_hash=bytes(row["secret_hash"]),
                scopes=tuple(parsed["scopes"]),
                allowed_cidrs=tuple(parsed.get("allowedCidrs") or []),
                status="revoked" if row["revoked_at_utc"] is not None else "active",
                version=int(parsed.get("version") or 1),
                created_at=created_at,
                updated_at=created_at,
                expires_at=_as_utc(row["expires_at_utc"]) if row["expires_at_utc"] is not None else None,
            )
        )
    keys.replace_workspace(workspace_id, loaded)


async def _require_workspace_admin(
    connection: AsyncConnection,
    workspace_id: UUID,
    principal_id: UUID,
) -> None:
    row = (
        await connection.execute(
            text(
                """
                SELECT role_code
                FROM public.workspace_members
                WHERE workspace_id = :workspace_id AND principal_id = :principal_id
                LIMIT 1
                """
            ),
            {"workspace_id": workspace_id, "principal_id": principal_id},
        )
    ).first()
    if row is None or row[0] != _ADMIN_ROLE:
        raise ApiKeyError("AUTH_SCOPE_REQUIRED", 403)


async def _insert_credential(connection: AsyncConnection, record: StoredApiKey) -> None:
    await connection.execute(
        text(
            """
            INSERT INTO public.api_credentials(
                id, workspace_id, public_id, secret_hash, permissions_json, expires_at_utc
            )
            VALUES (
                :id, :workspace_id, :public_id, :secret_hash,
                CAST(:permissions_json AS jsonb), :expires_at
            )
            """
        ),
        _credential_params(record),
    )


async def _update_credential(connection: AsyncConnection, record: StoredApiKey) -> None:
    await connection.execute(
        text(
            """
            UPDATE public.api_credentials
            SET secret_hash = :secret_hash,
                permissions_json = CAST(:permissions_json AS jsonb),
                expires_at_utc = :expires_at
            WHERE workspace_id = :workspace_id
              AND public_id = :public_id
              AND revoked_at_utc IS NULL
            """
        ),
        _credential_params(record),
    )


def _credential_params(record: StoredApiKey) -> dict[str, Any]:
    metadata = {
        "name": record.name,
        "prefix": record.prefix,
        "scopes": list(record.scopes),
        "allowedCidrs": list(record.allowed_cidrs),
        "version": record.version,
    }
    return {
        "id": record.internal_id,
        "workspace_id": record.workspace_id,
        "public_id": record.public_id,
        "secret_hash": record.secret_hash,
        "permissions_json": json.dumps(metadata, separators=(",", ":"), sort_keys=True),
        "expires_at": record.expires_at,
    }


async def _audit(
    connection: AsyncConnection,
    principal_id: UUID,
    action: str,
    record: StoredApiKey,
) -> None:
    await write_audit_event(
        connection,
        workspace_id=record.workspace_id,
        actor_id=str(principal_id),
        action=action,
        resource_type="api_credential",
        resource_id=record.public_id,
        details={
            "name": record.name,
            "prefix": record.prefix,
            "scopes": list(record.scopes),
            "version": record.version,
        },
    )


async def _outbox(connection: AsyncConnection, event_type: str, record: StoredApiKey) -> None:
    occurred = datetime.now(tz=UTC).isoformat()
    await enqueue_outbox_event(
        connection,
        OutboxEvent(
            workspace_id=record.workspace_id,
            event_type=event_type,
            aggregate_type="api_credential",
            aggregate_id=record.public_id,
            aggregate_sequence=record.version,
            cloud_event={
                "specversion": "1.0",
                "id": public_id("evt"),
                "source": "urn:edgemint:service:identity",
                "type": f"io.edgemint.{event_type}.v1",
                "subject": record.public_id,
                "time": occurred,
                "data": {
                    "apikeyId": record.public_id,
                    "aggregateVersion": record.version,
                    "occurredAt": occurred,
                    "action": event_type.removeprefix("api_key."),
                    "actorType": "user",
                },
            },
        ),
    )


def _metadata(raw: Any) -> dict[str, Any] | None:
    if isinstance(raw, str):
        raw = json.loads(raw)
    if not isinstance(raw, dict) or "name" not in raw or "prefix" not in raw or "scopes" not in raw:
        return None
    return raw


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)

