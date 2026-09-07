from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.routing.policy import RoutingPolicy


def policy_hash(policy: RoutingPolicy | None = None) -> str:
    active = policy or RoutingPolicy.load()
    payload = json.dumps(active.spec, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


@dataclass(frozen=True, slots=True)
class RoutingDecisionAuditService:
    async def record_decision(
        self,
        connection: AsyncConnection,
        *,
        task_attempt_id: UUID,
        task_id: str,
        router_epoch: int,
        ranked_candidates: list[dict[str, Any]],
        winner: dict[str, Any] | None,
        policy: RoutingPolicy | None = None,
    ) -> UUID:
        active = policy or RoutingPolicy.load()
        trace = {
            "assignmentMode": active.assignment_mode,
            "eligibleCount": sum(1 for row in ranked_candidates if row.get("eligible")),
            "candidateCount": len(ranked_candidates),
            "winnerWorkerId": winner.get("workerId") if winner else None,
            "winnerIneligibilityReasons": winner.get("ineligibilityReasons", []) if winner else [],
        }
        audit_id = (
            await connection.execute(
                text(
                    """
                    INSERT INTO public.routing_decision_audit(
                        task_attempt_id, task_id, router_epoch, policy_hash,
                        winner_worker_id, winner_score, candidates_json, decision_trace_json,
                        decided_at_utc
                    )
                    VALUES (
                        :task_attempt_id, :task_id, :router_epoch, :policy_hash,
                        :winner_worker_id, :winner_score,
                        CAST(:candidates_json AS jsonb), CAST(:decision_trace_json AS jsonb),
                        :decided_at_utc
                    )
                    RETURNING id
                    """
                ),
                {
                    "task_attempt_id": task_attempt_id,
                    "task_id": task_id,
                    "router_epoch": router_epoch,
                    "policy_hash": policy_hash(active),
                    "winner_worker_id": winner.get("workerId") if winner else None,
                    "winner_score": int(winner.get("score", 0)) if winner else 0,
                    "candidates_json": json.dumps(ranked_candidates),
                    "decision_trace_json": json.dumps(trace),
                    "decided_at_utc": datetime.now(UTC),
                },
            )
        ).scalar_one()
        return UUID(str(audit_id))
