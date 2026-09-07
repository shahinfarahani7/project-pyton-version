from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.results.entitlement_keys import evaluate_payload_idempotency
from edgemint.results.errors import result_error


def payload_digest(payload: dict[str, Any]) -> str:
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


@dataclass(frozen=True, slots=True)
class ExternalEffectReceipt:
    receipt_id: str
    is_new: bool
    conflict: bool
    payload_digest: str


class ExternalEffectService:
    """Record destination-scoped idempotency receipts for external payout/webhook effects."""

    async def record(
        self,
        connection: AsyncConnection,
        *,
        destination_type: str,
        destination_id: str,
        idempotency_key: str,
        payload: dict[str, Any],
        response: dict[str, Any] | None = None,
    ) -> ExternalEffectReceipt:
        digest = payload_digest(payload)
        row = (
            await connection.execute(
                text(
                    """
                    SELECT receipt_id, is_new, conflict
                    FROM public.record_external_effect_receipt(
                      :destination_type,
                      :destination_id,
                      :idempotency_key,
                      :payload_digest,
                      CAST(:response_json AS jsonb)
                    )
                    """
                ),
                {
                    "destination_type": destination_type,
                    "destination_id": destination_id,
                    "idempotency_key": idempotency_key,
                    "payload_digest": digest,
                    "response_json": json.dumps(response) if response is not None else None,
                },
            )
        ).mappings().first()
        if row is None:
            raise result_error("RESULT_VALIDATION_FAILED", detail="external effect receipt failed")
        if row["conflict"]:
            raise result_error(
                "IDEMPOTENCY_CONFLICT",
                detail="external effect idempotency key reused with different payload",
            )
        return ExternalEffectReceipt(
            receipt_id=str(row["receipt_id"]),
            is_new=bool(row["is_new"]),
            conflict=bool(row["conflict"]),
            payload_digest=digest,
        )

    @staticmethod
    def classify_replay(
        *,
        existing_digest: str | None,
        incoming_payload: dict[str, Any],
    ) -> str:
        return evaluate_payload_idempotency(
            existing_digest=existing_digest,
            incoming_digest=payload_digest(incoming_payload),
        )
