from __future__ import annotations

import secrets
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.building_blocks.settings import Settings, get_settings
from edgemint.routing.cost_estimator import EnvelopeTaskCostEstimator, TaskCostEstimator
from edgemint.routing.execution_plan_resolver import ExecutionPlan, resolve_execution_plan
from edgemint.routing.hard_eligibility import partition_candidates_by_hard_eligibility
from edgemint.routing.resource_budget import (
    EffectiveResourceBudgets,
    apply_contribution_budget,
    compute_effective_resource_budgets,
    load_contribution_budget_multiplier_bps,
)
from edgemint.routing.atomic_assignment import AtomicAssignmentTransaction
from edgemint.routing.failure_affinity import FailureAffinityService
from edgemint.routing.resource_reservations import ResourceReservationService
from edgemint.routing.routing_audit import RoutingDecisionAuditService
from edgemint.routing.errors import RouterServiceError, router_error
from edgemint.routing.fencing import (
    assert_monotonic_fence,
    assert_reassignment_budget,
    compute_tie_breaker,
    rank_queue_attempts,
    routing_decision_explanation,
)
from edgemint.routing.policy import RoutingPolicy
from edgemint.routing.runtime_compatibility import (
    is_runtime_compatible,
    runtime_incompatibility_reasons,
    task_runtime_class_for_task_type,
)
from edgemint.workers.device_capability import DeviceCapabilityReport
from edgemint.security.tokens import hash_session_token
from edgemint.security.lease_credentials import LeaseCredentialCipher

_TRANSIENT_ASSIGNMENT_ERRORS: frozenset[str] = frozenset(
    {
        "WORKER_NOT_ELIGIBLE",
        "RESOURCE_RESERVATION_FAILED",
        "EXCLUSIVE_GROUP_SATURATED",
        "CPU_BUDGET_EXCEEDED",
        "MEMORY_BUDGET_EXCEEDED",
        "STORAGE_BUDGET_EXCEEDED",
        "WORKER_CAPACITY_EXHAUSTED",
    }
)


@dataclass
class RouterService:
    settings: Settings = field(default_factory=get_settings)
    policy: RoutingPolicy = field(default_factory=RoutingPolicy.load)
    cost_estimator: TaskCostEstimator = field(default_factory=EnvelopeTaskCostEstimator)
    resource_reservations: ResourceReservationService = field(default_factory=ResourceReservationService)
    atomic_assignment: AtomicAssignmentTransaction = field(default_factory=AtomicAssignmentTransaction)
    failure_affinity: FailureAffinityService = field(default_factory=FailureAffinityService)
    routing_audit: RoutingDecisionAuditService = field(default_factory=RoutingDecisionAuditService)

    def resolve_execution_plan(
        self,
        *,
        task_type: str,
        estimated_input_tokens: int = 0,
        page_count: int = 0,
    ) -> ExecutionPlan:
        return resolve_execution_plan(
            task_type=task_type,
            estimated_input_tokens=estimated_input_tokens,
            page_count=page_count,
        )

    async def contribution_budget_multiplier_bps_for_worker(
        self,
        connection: AsyncConnection,
        *,
        worker_id: UUID,
    ) -> int:
        """Scheduler hook: user consent level caps per-device resource budgets."""
        return await load_contribution_budget_multiplier_bps(connection, worker_id=worker_id)

    def effective_cpu_budget_units(
        self,
        *,
        device_cpu_capacity: int,
        budget_multiplier_bps: int,
    ) -> int:
        return apply_contribution_budget(
            capacity_units=device_cpu_capacity,
            budget_multiplier_bps=budget_multiplier_bps,
        )

    def compute_effective_resource_budgets_for_capability(
        self,
        *,
        capability: DeviceCapabilityReport,
        budget_multiplier_bps: int,
    ) -> EffectiveResourceBudgets:
        return compute_effective_resource_budgets(
            capability=capability,
            contribution_multiplier_bps=budget_multiplier_bps,
        )

    def runtime_compatible_for_task(
        self,
        *,
        worker_runtime_classes: list[str],
        task_type: str,
        device_tier: str | None = None,
        active_runtime_classes: list[str] | None = None,
        concurrency_certified: bool = False,
    ) -> bool:
        task_runtime_class = task_runtime_class_for_task_type(task_type)
        if task_runtime_class is None:
            return True
        return is_runtime_compatible(
            worker_runtime_classes=worker_runtime_classes,
            task_runtime_class=task_runtime_class,
            device_tier=device_tier,
            active_runtime_classes=active_runtime_classes,
            concurrency_certified=concurrency_certified,
        )

    async def calibration_factor_bps_for_device(
        self,
        connection: AsyncConnection,
        *,
        worker_device_id: UUID,
        active_artifact_id: str | None = None,
        active_runtime_version: str | None = None,
    ) -> int:
        from edgemint.routing.calibration import resolve_calibration_factor_bps_for_device

        return await resolve_calibration_factor_bps_for_device(
            connection,
            worker_device_id=worker_device_id,
            active_artifact_id=active_artifact_id,
            active_runtime_version=active_runtime_version,
        )

    def build_versioned_prediction_record(
        self,
        *,
        base_duration_ms: int,
        base_peak_memory_bytes: int,
        model_resident: bool = False,
        warmup_completed: bool = False,
    ) -> dict[str, object]:
        from edgemint.routing.calibration_prediction import (
            build_versioned_prediction,
            resolve_prediction_phase,
        )

        phase = resolve_prediction_phase(
            model_resident=model_resident,
            warmup_completed=warmup_completed,
        )
        return build_versioned_prediction(
            base_duration_ms=base_duration_ms,
            base_peak_memory_bytes=base_peak_memory_bytes,
            metrics=None,
            identity=None,
            measured_at=None,
            phase=phase,
        ).as_dict()

    def hard_eligibility_bypass_enabled(self) -> bool:
        return (
            self.settings.environment in {"development", "test"}
            and bool(getattr(self.settings, "router_bypass_hard_eligibility_filter", False))
        )

    def apply_hard_eligibility_filter(
        self,
        candidates: list[dict[str, Any]],
    ) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
        """Section 10: ineligible workers never reach scoring."""
        return partition_candidates_by_hard_eligibility(
            candidates,
            policy=self.policy,
            bypass=self.hard_eligibility_bypass_enabled(),
        )

    def evaluate(self, candidate_input: dict[str, Any]) -> dict[str, Any]:
        from edgemint.routing.engine import evaluate_candidate

        return evaluate_candidate(
            candidate_input,
            policy=self.policy,
            bypass_hard_eligibility=self.hard_eligibility_bypass_enabled(),
        )

    def rank_workers(
        self,
        *,
        task_id: str,
        router_epoch: int,
        candidates: list[dict[str, Any]],
    ) -> list[dict[str, Any]]:
        secret = self.settings.jwt_signing_secret or "edgemint-development-signing-secret"
        eligible_candidates, ineligible_candidates = self.apply_hard_eligibility_filter(candidates)

        ranked: list[dict[str, Any]] = []
        for item in eligible_candidates:
            worker_id = str(item["workerId"])
            evaluation = self.evaluate({**item["input"], "workerId": worker_id})
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

        for item in ineligible_candidates:
            worker_id = str(item["workerId"])
            ranked.append(
                {
                    "eligible": False,
                    "ineligibilityReasons": list(item["ineligibilityReasons"]),
                    "score": 0,
                    "tieBreaker": self.policy.spec["score"]["tieBreaker"].split("(")[0],
                    "workerId": worker_id,
                    "tieBreakDigest": compute_tie_breaker(
                        task_id=task_id,
                        worker_id=worker_id,
                        router_epoch=router_epoch,
                        secret=secret,
                    ),
                }
            )
        return ranked

    def rank_task_attempts(self, attempts: list[dict[str, Any]]) -> list[str]:
        from edgemint.routing.fair_queue import rank_task_attempts

        return rank_task_attempts(attempts, policy=self.policy)

    def select_worker(
        self,
        *,
        task_id: str,
        router_epoch: int,
        candidates: list[dict[str, Any]],
    ) -> dict[str, Any] | None:
        ranked = self.rank_workers(task_id=task_id, router_epoch=router_epoch, candidates=candidates)
        for row in ranked:
            if row["eligible"]:
                return row
        return None

    async def rank_workers_with_audit(
        self,
        connection: AsyncConnection,
        *,
        task_attempt_id: UUID,
        task_id: str,
        router_epoch: int,
        candidates: list[dict[str, Any]],
    ) -> tuple[dict[str, Any] | None, UUID]:
        ranked = self.rank_workers(task_id=task_id, router_epoch=router_epoch, candidates=candidates)
        winner = next((row for row in ranked if row["eligible"]), None)
        audit_id = await self.routing_audit.record_decision(
            connection,
            task_attempt_id=task_attempt_id,
            task_id=task_id,
            router_epoch=router_epoch,
            ranked_candidates=ranked,
            winner=winner,
            policy=self.policy,
        )
        return winner, audit_id

    async def assign_attempt_with_scheduler_stack(
        self,
        connection: AsyncConnection,
        *,
        task_attempt_id: UUID,
        task_id: str,
        router_epoch: int,
        router_instance_id: str,
        candidates: list[dict[str, Any]],
        prior_assignments: int = 0,
        edge_wait_seconds: float = 0,
        customer_allows_cloud: bool = True,
        task_run_usage: TaskRunBudgetUsage | None = None,
    ) -> dict[str, Any]:
        """Section 20: rank workers, audit, then atomically reserve + assign in order."""
        from edgemint.governance.runtime_activation import assert_runtime_activation_gate_open
        from edgemint.routing.cloud_fallback import evaluate_cloud_fallback

        await assert_runtime_activation_gate_open(connection, settings=self.settings)
        from edgemint.routing.task_run_budget import (
            TaskRunBudgetUsage,
            combine_assignment_budget_checks,
            load_task_run_budget_limits,
        )

        usage = task_run_usage or TaskRunBudgetUsage(
            attempt_count=1,
            assignment_count=0,
            cloud_fallback_count=0,
        )
        limits = load_task_run_budget_limits(self.policy)
        combine_assignment_budget_checks(
            prior_assignments_in_attempt=prior_assignments,
            max_worker_reassignments=self.policy.max_worker_reassignments,
            task_run_usage=usage,
            task_run_limits=limits,
        )

        enriched_candidates: list[dict[str, Any]] = []
        for item in candidates:
            candidate = dict(item)
            input_payload = dict(candidate.get("input") or {})
            device_id = candidate.get("workerDeviceId")
            if device_id and "calibrationFactorBps" not in input_payload:
                input_payload["calibrationFactorBps"] = await self.calibration_factor_bps_for_device(
                    connection,
                    worker_device_id=UUID(str(device_id)),
                )
            candidate["input"] = input_payload
            enriched_candidates.append(candidate)

        rank_candidates = [
            {
                "workerId": str(item["workerId"]),
                "input": {**item["input"], "workerId": str(item["workerId"])},
            }
            for item in enriched_candidates
        ]
        ranked = self.rank_workers(
            task_id=task_id,
            router_epoch=router_epoch,
            candidates=rank_candidates,
        )
        audit_id = await self.routing_audit.record_decision(
            connection,
            task_attempt_id=task_attempt_id,
            task_id=task_id,
            router_epoch=router_epoch,
            ranked_candidates=ranked,
            winner=next((row for row in ranked if row["eligible"]), None),
            policy=self.policy,
        )

        for row in ranked:
            if not row["eligible"]:
                continue
            candidate = next(
                item for item in enriched_candidates if str(item["workerId"]) == row["workerId"]
            )
            try:
                body = await self.acquire_assignment_lease(
                    connection,
                    task_attempt_id=task_attempt_id,
                    worker_id=UUID(str(candidate["workerId"])),
                    worker_device_id=UUID(str(candidate["workerDeviceId"])),
                    router_instance_id=router_instance_id,
                )
                return {
                    **body,
                    "auditId": str(audit_id),
                    "workerId": row["workerId"],
                    "score": int(row["score"]),
                    "schedulerTrace": {
                        "rankedWorkerIds": [item["workerId"] for item in ranked],
                        "selectedWorkerId": row["workerId"],
                    },
                }
            except RouterServiceError as exc:
                if exc.code in _TRANSIENT_ASSIGNMENT_ERRORS:
                    continue
                raise

        fallback = evaluate_cloud_fallback(
            edge_wait_seconds=edge_wait_seconds,
            policy=self.policy,
            customer_allows_cloud=customer_allows_cloud,
            task_run_usage=usage,
            task_run_limits=limits,
        )
        if fallback.permitted:
            return {
                "assignmentMode": "cloud_fallback",
                "auditId": str(audit_id),
                "cloudFallback": {
                    "permitted": fallback.permitted,
                    "reason": fallback.reason,
                    "edgeWaitSeconds": fallback.edgeWaitSeconds,
                    "cloudAfterSeconds": fallback.cloudAfterSeconds,
                    "policyHash": fallback.policyHash,
                },
            }

        raise router_error("NO_CAPACITY", detail="scheduler stack exhausted eligible workers")

    def workspace_fair_queue_metrics(self, attempts: list[dict[str, Any]]) -> list[dict[str, Any]]:
        from edgemint.routing.fair_queue_metrics import workspace_fair_queue_metrics

        return workspace_fair_queue_metrics(attempts)

    def compute_queue_cost_units(self, estimated_execution_ms: int) -> int:
        from edgemint.routing.workspace_drr import compute_queue_cost_units, load_admission_backpressure_policy

        policy = load_admission_backpressure_policy()
        divisor = int((policy.get("drr") or {}).get("costUnitsDivisorMs", 1000))
        return compute_queue_cost_units(estimated_execution_ms, divisor_ms=divisor)

    def evaluate_admission_backpressure(
        self,
        *,
        workspace_id: str,
        queued_count: int,
        active_count: int,
        input_cost_units: int,
        outbox_pending: int = 0,
        upload_in_flight: int = 0,
        validation_backlog: int = 0,
    ) -> dict[str, Any]:
        from edgemint.routing.admission_backpressure import (
            PipelinePressureSnapshot,
            evaluate_admission_backpressure,
        )

        decision = evaluate_admission_backpressure(
            workspace_id=workspace_id,
            queued_count=queued_count,
            active_count=active_count,
            input_cost_units=input_cost_units,
            pipeline=PipelinePressureSnapshot(
                outbox_pending=outbox_pending,
                upload_in_flight=upload_in_flight,
                validation_backlog=validation_backlog,
            ),
        )
        return {
            "permitted": decision.permitted,
            "reasonCode": decision.reason_code.value,
            "detail": decision.detail,
            "boundedWaitSeconds": decision.bounded_wait_seconds,
        }

    def rank_task_attempts_with_drr(
        self,
        attempts: list[dict[str, Any]],
        *,
        drr_state: Any | None = None,
    ) -> list[str]:
        from edgemint.routing.fair_queue import rank_task_attempts
        from edgemint.routing.workspace_drr import WorkspaceDrrState, attach_workspace_deficits

        state = drr_state or WorkspaceDrrState()
        enriched = attach_workspace_deficits(attempts, state)
        return rank_task_attempts(enriched, policy=self.policy)

    def collect_operating_signals(
        self,
        *,
        attempts: list[dict[str, Any]],
        drr_state: Any | None = None,
        outbox_pending: int = 0,
        upload_in_flight: int = 0,
        validation_backlog: int = 0,
        admission_blocked_reason: str | None = None,
    ) -> list[dict[str, Any]]:
        from edgemint.routing.admission_backpressure import BackpressureDecision, BackpressureReason
        from edgemint.routing.admission_backpressure import PipelinePressureSnapshot
        from edgemint.routing.operating_signals import collect_operating_signals, reveal_primary_blocker
        from edgemint.routing.workspace_drr import WorkspaceDrrState

        state = drr_state or WorkspaceDrrState()
        pipeline = PipelinePressureSnapshot(
            outbox_pending=outbox_pending,
            upload_in_flight=upload_in_flight,
            validation_backlog=validation_backlog,
        )
        admission = None
        if admission_blocked_reason:
            admission = BackpressureDecision(
                permitted=False,
                reason_code=BackpressureReason(admission_blocked_reason),
            )
        signals = collect_operating_signals(
            attempts=attempts,
            drr_state=state,
            pipeline=pipeline,
            admission=admission,
        )
        blocker = reveal_primary_blocker(signals)
        if blocker and signals:
            signals[0]["primaryBlocker"] = blocker
        return signals

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
        if self.settings.worker_resource_reservations_enabled:
            task_type = await self.atomic_assignment.load_task_type_for_attempt(
                connection,
                task_attempt_id=task_attempt_id,
            )
            body = await self.atomic_assignment.acquire_with_reservation(
                connection,
                task_attempt_id=task_attempt_id,
                worker_id=worker_id,
                worker_device_id=worker_device_id,
                router_instance_id=router_instance_id,
                lease_token=lease_token,
                lease_token_hash=token_hash,
                lease_seconds=self.policy.spec["timeouts"]["leaseSeconds"],
                delivery_seconds=self.policy.spec["timeouts"]["assignmentDeliverySeconds"],
                auto_start_grace_seconds=self.policy.spec["timeouts"]["autoStartGraceSeconds"],
                heartbeat_max_age_seconds=self.policy.eligibility["heartbeatMaximumAgeSeconds"],
                min_trust_bps=self.policy.eligibility["minimumTrustMilli"] * 10,
                task_type=task_type,
            )
            return {
                **body,
                "assignmentMode": self.policy.assignment_mode,
            }

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
        token_ciphertext = LeaseCredentialCipher.from_settings(self.settings).encrypt(
            lease_token,
            worker_device_id=worker_device_id,
        )
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

    def classify_retry(self, failure_code: str, *, task_type: str | None = None) -> dict[str, str | bool]:
        from edgemint.routing.retry_classifier import RetryClass, classify_failure_code
        from edgemint.routing.retry_policy_matrix import get_retry_policy_matrix

        if task_type:
            retry_class = get_retry_policy_matrix().resolve_retry_class(
                task_type=task_type,
                failure_code=failure_code,
            )
        else:
            retry_class = classify_failure_code(failure_code)
        return {
            "retryClass": retry_class.value,
            "requiresStrongerWorker": retry_class == RetryClass.STRONGER_WORKER,
            "retryPermitted": retry_class != RetryClass.NO_RETRY,
        }

    def escalated_verification_tier_for_failure(
        self,
        *,
        current_tier: str,
        failure_code: str,
    ) -> str:
        from edgemint.routing.quality_escalation import escalated_verification_tier

        return escalated_verification_tier(current_tier=current_tier, failure_code=failure_code)

    @staticmethod
    def rank_attempts_for_tests(attempts: list[dict[str, Any]]) -> list[str]:
        from edgemint.routing.fair_queue import rank_task_attempts

        return rank_task_attempts(attempts)
