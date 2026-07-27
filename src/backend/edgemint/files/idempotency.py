from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection


@dataclass(frozen=True, slots=True)
class IdempotencyResult:
    replay: bool
    status_code: int
    body: dict[str, Any]


def request_hash(payload: dict[str, Any]) -> str:
    canonical = json.dumps(payload, separators=(",", ":"), sort_keys=True)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def idempotency_scope(*, operation_id: str, principal_id: UUID, workspace_id: UUID) -> str:
    return f"{operation_id}:{principal_id}:{workspace_id}"


async def begin_idempotent_command(
    connection: AsyncConnection,
    *,
    workspace_id: UUID,
    scope: str,
    idempotency_key: str,
    payload: dict[str, Any],
) -> IdempotencyResult | None:
    digest = request_hash(payload)
    existing = (
        await connection.execute(
            text(
                """
                SELECT request_hash, response_status, response_json
                FROM public.idempotency_records
                WHERE workspace_id = :workspace_id
                  AND scope = :scope
                  AND idempotency_key = :idempotency_key
                LIMIT 1
                """
            ),
            {
                "workspace_id": workspace_id,
                "scope": scope,
                "idempotency_key": idempotency_key,
            },
        )
    ).mappings().first()
    if existing is not None:
        if existing["request_hash"] != digest:
            return IdempotencyResult(replay=True, status_code=409, body={"code": "IDEMPOTENCY_CONFLICT"})
        if existing["response_status"] is not None and existing["response_json"] is not None:
            return IdempotencyResult(
                replay=True,
                status_code=int(existing["response_status"]),
                body=dict(existing["response_json"]),
            )
        return None
    await connection.execute(
        text(
            """
            INSERT INTO public.idempotency_records(
                workspace_id, scope, idempotency_key, request_hash
            )
            VALUES (:workspace_id, :scope, :idempotency_key, :request_hash)
            """
        ),
        {
            "workspace_id": workspace_id,
            "scope": scope,
            "idempotency_key": idempotency_key,
            "request_hash": digest,
        },
    )
    return None


async def complete_idempotent_command(
    connection: AsyncConnection,
    *,
    workspace_id: UUID,
    scope: str,
    idempotency_key: str,
    status_code: int,
    body: dict[str, Any],
) -> None:
    await connection.execute(
        text(
            """
            UPDATE public.idempotency_records
            SET response_status = :response_status,
                response_json = CAST(:response_json AS jsonb)
            WHERE workspace_id = :workspace_id
              AND scope = :scope
              AND idempotency_key = :idempotency_key
            """
        ),
        {
            "workspace_id": workspace_id,
            "scope": scope,
            "idempotency_key": idempotency_key,
            "response_status": status_code,
            "response_json": json.dumps(body, separators=(",", ":"), sort_keys=True),
        },
    )
