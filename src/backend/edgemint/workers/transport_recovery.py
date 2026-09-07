from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from enum import StrEnum
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.workers.errors import worker_error


class TransportEventKind(StrEnum):
    ACK = "ack"
    PROGRESS = "progress"
    CHECKPOINT = "checkpoint"
    RESULT = "result"


class SubmissionClassification(StrEnum):
    TRANSPORT_FRESH = "transport_fresh"
    TRANSPORT_REPLAY = "transport_replay"
    TRANSPORT_CONFLICT = "transport_conflict"
    TASK_RETRY_UNAUTHORIZED = "task_retry_unauthorized"


@dataclass(frozen=True, slots=True)
class TransportRecordResult:
    classification: SubmissionClassification
    aggregate_sequence: int
    is_new: bool


def transport_payload_digest(payload: dict[str, Any]) -> str:
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def transport_event_identity(
    *,
    assignment_id: str,
    fence_token: int,
    event_kind: TransportEventKind,
    sequence: int | None = None,
    result_sha256: str | None = None,
) -> str:
    if event_kind == TransportEventKind.ACK:
        return f"ack:{assignment_id}:{fence_token}"
    if event_kind == TransportEventKind.PROGRESS:
        if sequence is None:
            raise ValueError("progress transport identity requires sequence")
        return f"progress:{assignment_id}:{fence_token}:{sequence}"
    if event_kind == TransportEventKind.CHECKPOINT:
        if sequence is None:
            raise ValueError("checkpoint transport identity requires sequence")
        return f"checkpoint:{assignment_id}:{fence_token}:{sequence}"
    if event_kind == TransportEventKind.RESULT:
        if result_sha256 is None:
            raise ValueError("result transport identity requires result_sha256")
        return f"result:{assignment_id}:{fence_token}:{result_sha256}"
    raise ValueError(f"unsupported transport event kind: {event_kind}")


def classify_transport_submission(
    *,
    is_new: bool,
    conflict: bool,
    unauthorized_task_retry: bool = False,
) -> SubmissionClassification:
    if unauthorized_task_retry:
        return SubmissionClassification.TASK_RETRY_UNAUTHORIZED
    if conflict:
        return SubmissionClassification.TRANSPORT_CONFLICT
    if is_new:
        return SubmissionClassification.TRANSPORT_FRESH
    return SubmissionClassification.TRANSPORT_REPLAY


def aggregate_sequence_for_transport(
    *,
    fence_token: int,
    event_kind: TransportEventKind,
    sequence: int,
) -> int:
    band = {
        TransportEventKind.ACK: 1,
        TransportEventKind.PROGRESS: 2_000_000,
        TransportEventKind.CHECKPOINT: 3_000_000,
        TransportEventKind.RESULT: 900_000_000,
    }[event_kind]
    return fence_token * 1_000_000_000 + band + sequence


class TransportRecoveryService:
    """Server-side transport recovery boundary; does not grant scheduling authority."""

    async def record(
        self,
        connection: AsyncConnection,
        *,
        workspace_id: UUID,
        assignment_id: UUID,
        event_kind: TransportEventKind,
        event_identity: str,
        payload: dict[str, Any],
        aggregate_sequence: int,
    ) -> TransportRecordResult:
        digest = transport_payload_digest(payload)
        row = (
            await connection.execute(
                text(
                    """
                    SELECT is_new, conflict, stored_aggregate_sequence
                    FROM public.record_assignment_transport_receipt(
                      :workspace_id,
                      :assignment_id,
                      :event_kind,
                      :event_identity,
                      :payload_digest,
                      :aggregate_sequence
                    )
                    """
                ),
                {
                    "workspace_id": workspace_id,
                    "assignment_id": assignment_id,
                    "event_kind": str(event_kind),
                    "event_identity": event_identity,
                    "payload_digest": digest,
                    "aggregate_sequence": aggregate_sequence,
                },
            )
        ).mappings().first()
        if row is None:
            raise worker_error("INPUT_SCHEMA_INVALID", detail="transport receipt failed")
        classification = classify_transport_submission(
            is_new=bool(row["is_new"]),
            conflict=bool(row["conflict"]),
        )
        if classification == SubmissionClassification.TRANSPORT_CONFLICT:
            raise worker_error(
                "INPUT_SCHEMA_INVALID",
                detail="transport idempotency identity reused with different payload",
            )
        return TransportRecordResult(
            classification=classification,
            aggregate_sequence=int(row["stored_aggregate_sequence"]),
            is_new=bool(row["is_new"]),
        )
