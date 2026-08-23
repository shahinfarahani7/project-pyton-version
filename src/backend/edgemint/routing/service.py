from __future__ import annotations

import secrets
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.building_blocks.settings import Settings, get_settings
from edgemint.routing.engine import evaluate_candidate
from edgemint.routing.errors import router_error
from edgemint.routing.fencing import (
    assert_monotonic_fence,
    assert_reassignment_budget,
    compute_tie_breaker,
    rank_queue_attempts,
    routing_decision_explanation,
)
from edgemint.routing.policy import RoutingPolicy
from edgemint.security.tokens import hash_session_token
from edgemint.security.lease_credentials import LeaseCredentialCipher


@dataclass
class RouterService:
    settings: Settings = field(default_factory=get_settings)
    policy: RoutingPolicy = field(default_factory=RoutingPolicy.load)

    def evaluate(self, candidate_input: dict[str, Any]) -> dict[str, Any]:
        return evaluate_candidate(candidate_input, policy=self.policy)

    def rank_workers(
        self,
        *,
        task_id: str,
        router_epoch: int,
        candidates: list[dict[str, Any]],
    ) -> list[dict[str, Any]]:
        secret = self.settings.jwt_signing_secret or "edgemint-development-signing-secret"
        ranked: list[dict[str, Any]] = []
        for item in candidates:
            worker_id = str(item["workerId"])
            evaluation = self.evaluate(item["input"])
            ranked.append(
                {
                    **evaluation,
                    "workerId": worker_id,
                    "tieBreakDigest": compute_tie_breaker(
                        task_id=task_id,
                        worker_id=worker_id,
                        router_epoch=router_epoch,
                        secret=secret,
                    ),
                }
            )
        ranked.sort(key=lambda row: (-int(row["score"]), row["tieBreakDigest"], row["workerId"]))
        return ranked

    async def select_next_attempt(
        self,
        connection: AsyncConnection,
        *,
        router_instance_id: str,
        claim_seconds: int = 30,
        candidate_window: int = 200,
    ) -> UUID | None:
        attempt_id = (
            await connection.execute(
                text(
                    "SELECT public.select_next_routable_attempt("
                    ":router_instance_id, :claim_seconds, :candidate_window)"
                ),
                {
                    "router_instance_id": router_instance_id,
                    "claim_seconds": claim_seconds,
                    "candidate_window": candidate_window,
                },
            )
        ).scalar_one_or_none()
        return UUID(str(attempt_id)) if attempt_id else None

    async def acquire_assignment_lease(
        self,
        connection: AsyncConnection,
        *,
        task_attempt_id: UUID,
        worker_id: UUID,
        worker_device_id: UUID,
        router_instance_id: str,
    ) -> dict[str, Any]:
        lease_token = secrets.token_urlsafe(48)
        token_hash = hash_session_token(lease_token)
        token_ciphertext = LeaseCredentialCipher.from_settings(self.settings).encrypt(
            lease_token,
            worker_device_id=worker_device_id,
        )
        row = (
            await connection.execute(
                text(
                    """
                    SELECT assignment_id, fence_token, lease_expires_at_utc
                    FROM public.acquire_assignment_lease(
                        :task_attempt_id, :worker_id, :worker_device_id, :router_instance_id,
                        :lease_token_hash, :lease_seconds, :delivery_seconds,
                        :auto_start_grace_seconds, :heartbeat_max_age_seconds, :min_trust_bps
                    )
                    """
                ),
                {
                    "task_attempt_id": task_attempt_id,
                    "worker_id": worker_id,
                    "worker_device_id": worker_device_id,
                    "router_instance_id": router_instance_id,
                    "lease_token_hash": token_hash,
                    "lease_seconds": self.policy.spec["timeouts"]["leaseSeconds"],
                    "delivery_seconds": self.policy.spec["timeouts"]["assignmentDeliverySeconds"],
                    "auto_start_grace_seconds": self.policy.spec["timeouts"]["autoStartGraceSeconds"],
                    "heartbeat_max_age_seconds": self.policy.eligibility["heartbeatMaximumAgeSeconds"],
                    "min_trust_bps": self.policy.eligibility["minimumTrustMilli"] * 10,
                },
            )
        ).mappings().first()
        if row is None:
            raise router_error("WORKER_NOT_ELIGIBLE")
        await connection.execute(
            text(
                """
                INSERT INTO public.assignment_lease_credentials(
                    assignment_id, worker_device_id, lease_token_ciphertext
                )
                VALUES (:assignment_id, :worker_device_id, :lease_token_ciphertext)
                """
            ),
            {
                "assignment_id": row["assignment_id"],
                "worker_device_id": worker_device_id,
                "lease_token_ciphertext": token_ciphertext,
            },
        )
        return {
            "assignmentId": str(row["assignment_id"]),
            "fenceToken": int(row["fence_token"]),
            "leaseToken": lease_token,
            "leaseExpiresAt": row["lease_expires_at_utc"],
            "assignmentMode": self.policy.assignment_mode,
        }

    async def renew_assignment_lease(
        self,
        connection: AsyncConnection,
        *,
        assignment_id: UUID,
        worker_device_id: UUID,
        fence_token: int,
        lease_token: str,
        sequence: int,
    ) -> datetime:
        expiry = (
            await connection.execute(
                text(
                    """
                    SELECT public.renew_auto_assignment_lease(
                        :assignment_id, :worker_device_id, :fence_token,
                        :lease_token_hash, :sequence, :lease_seconds
                    )
                    """
                ),
                {
                    "assignment_id": assignment_id,
                    "worker_device_id": worker_device_id,
                    "fence_token": fence_token,
                    "lease_token_hash": hash_session_token(lease_token),
                    "sequence": sequence,
                    "lease_seconds": self.policy.spec["timeouts"]["leaseSeconds"],
                },
            )
        ).scalar_one_or_none()
        if expiry is None:
            raise router_error("LEASE_RENEWAL_REJECTED")
        return expiry

    async def validate_fence_for_submission(
        self,
        connection: AsyncConnection,
        *,
        assignment_id: UUID,
        worker_device_id: UUID,
        fence_token: int,
    ) -> None:
        row = (
            await connection.execute(
                text(
                    """
                    SELECT fence_token, status
                    FROM public.assignments
                    WHERE id = :assignment_id AND worker_device_id = :worker_device_id
                    """
                ),
                {"assignment_id": assignment_id, "worker_device_id": worker_device_id},
            )
        ).mappings().first()
        if row is None:
            raise router_error("TENANT_RESOURCE_NOT_FOUND", detail="assignment not found")
        if str(row["status"]) not in {"leased", "running"}:
            raise router_error("ASSIGNMENT_STALE_FENCE", detail="assignment not active")
        assert_monotonic_fence(presented=fence_token, current=int(row["fence_token"]))

    def explain_decision(
        self,
        *,
        attempt_id: str,
        worker_id: str,
        candidate_input: dict[str, Any],
    ) -> dict[str, Any]:
        evaluation = self.evaluate(candidate_input)
        return routing_decision_explanation(
            attempt_id=attempt_id,
            worker_id=worker_id,
            score=int(evaluation["score"]),
            eligible=bool(evaluation["eligible"]),
            reasons=list(evaluation["ineligibilityReasons"]),
        )

    def assert_no_worker_confirmation_api(self) -> None:
        if self.policy.per_task_worker_confirmation:
            raise router_error("INPUT_SCHEMA_INVALID", detail="per-task confirmation forbidden")

    def cloud_fallback_due(self, *, edge_wait_seconds: float) -> bool:
        return edge_wait_seconds >= float(self.policy.cloud_after_seconds)

    def check_reassignment_budget(self, *, prior_assignments: int) -> None:
        assert_reassignment_budget(
            assignment_count=prior_assignments,
            max_reassignments=self.policy.max_worker_reassignments,
        )

    @staticmethod
    def rank_attempts_for_tests(attempts: list[dict[str, Any]]) -> list[str]:
        from edgemint.routing.fencing import QueueAttempt

        parsed = [
            QueueAttempt(
                attempt_id=str(item["attemptId"]),
                workspace_id=str(item["workspaceId"]),
                priority_bps=int(item["priorityBps"]),
                submitted_at=item["submittedAt"],
                deadline_at=item.get("deadlineAt"),
                task_id=str(item["taskId"]),
                deficit_units=int(item.get("deficitUnits", 0)),
                waiting_seconds=float(item.get("waitingSeconds", 0)),
            )
            for item in attempts
        ]
        return [item.attempt_id for item in rank_queue_attempts(parsed)]
