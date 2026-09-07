from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.results.entitlement_keys import (
    DEFAULT_ENTITLEMENT_COMPONENT,
    entitlement_business_key,
)
from edgemint.results.errors import result_error
from edgemint.tasks.task_run import TaskRunStatus


VALIDATOR_VERSION = "result-validator-v1@1.0.0"


@dataclass(frozen=True, slots=True)
class PinnedCandidate:
    candidate_id: UUID
    is_new: bool


@dataclass(frozen=True, slots=True)
class AcceptanceOutcome:
    terminal_committed: bool
    entitlement_id: UUID
    entitlement_is_new: bool
    idempotency_receipt: str


class ResultAcceptanceService:
    """Immutable candidate pinning, validation gating, and entitlement uniqueness (v2 §50–51)."""

    async def pin_candidate(
        self,
        connection: AsyncConnection,
        *,
        workspace_id: UUID,
        task_run_id: UUID,
        task_attempt_id: UUID,
        assignment_id: UUID,
        generation: int,
        result_sha256: str,
        worker_device_id: UUID,
        fence_token: int,
    ) -> PinnedCandidate:
        row = (
            await connection.execute(
                text(
                    """
                    SELECT candidate_id, is_new
                    FROM public.pin_result_candidate(
                      :workspace_id,
                      :task_run_id,
                      :task_attempt_id,
                      :assignment_id,
                      :generation,
                      :result_sha256,
                      :worker_device_id,
                      :fence_token
                    )
                    """
                ),
                {
                    "workspace_id": workspace_id,
                    "task_run_id": task_run_id,
                    "task_attempt_id": task_attempt_id,
                    "assignment_id": assignment_id,
                    "generation": generation,
                    "result_sha256": result_sha256,
                    "worker_device_id": worker_device_id,
                    "fence_token": fence_token,
                },
            )
        ).mappings().first()
        if row is None or row["candidate_id"] is None:
            raise result_error("RESULT_VALIDATION_FAILED", detail="failed to pin result candidate")
        return PinnedCandidate(
            candidate_id=UUID(str(row["candidate_id"])),
            is_new=bool(row["is_new"]),
        )

    async def record_validation(
        self,
        connection: AsyncConnection,
        *,
        workspace_id: UUID,
        candidate_id: UUID,
        passed: bool,
        failure_code: str | None = None,
        detail: str | None = None,
    ) -> UUID:
        status = "passed" if passed else "failed"
        validation_id = (
            await connection.execute(
                text(
                    """
                    SELECT public.record_result_validation(
                      :workspace_id,
                      :candidate_id,
                      :validation_status,
                      :validator_version,
                      :failure_code,
                      :detail
                    ) AS validation_id
                    """
                ),
                {
                    "workspace_id": workspace_id,
                    "candidate_id": candidate_id,
                    "validation_status": status,
                    "validator_version": VALIDATOR_VERSION,
                    "failure_code": failure_code,
                    "detail": detail,
                },
            )
        ).scalar_one()
        return UUID(str(validation_id))

    async def accept_outcome(
        self,
        connection: AsyncConnection,
        *,
        workspace_id: UUID,
        task_run_id: UUID,
        candidate_id: UUID,
        worker_device_id: UUID,
        amount_micro_eur: int = 0,
        terminal_status: TaskRunStatus = TaskRunStatus.SUCCEEDED,
        terminal_outcome: str = "assignment_complete",
        entitlement_component_id: str = DEFAULT_ENTITLEMENT_COMPONENT,
    ) -> AcceptanceOutcome:
        if amount_micro_eur < 0:
            raise result_error("INPUT_SCHEMA_INVALID", detail="negative reward amount")
        row = (
            await connection.execute(
                text(
                    """
                    SELECT terminal_committed, entitlement_id, entitlement_is_new, idempotency_receipt
                    FROM public.accept_task_run_with_entitlement(
                      :workspace_id,
                      :task_run_id,
                      :candidate_id,
                      :worker_device_id,
                      :amount_micro_eur,
                      :terminal_status,
                      :terminal_outcome,
                      :entitlement_component_id
                    )
                    """
                ),
                {
                    "workspace_id": workspace_id,
                    "task_run_id": task_run_id,
                    "candidate_id": candidate_id,
                    "worker_device_id": worker_device_id,
                    "amount_micro_eur": amount_micro_eur,
                    "terminal_status": str(terminal_status),
                    "terminal_outcome": terminal_outcome,
                    "entitlement_component_id": entitlement_component_id,
                },
            )
        ).mappings().first()
        if row is None or row["entitlement_id"] is None:
            raise result_error("RESULT_VALIDATION_FAILED", detail="acceptance commit failed")
        return AcceptanceOutcome(
            terminal_committed=bool(row["terminal_committed"]),
            entitlement_id=UUID(str(row["entitlement_id"])),
            entitlement_is_new=bool(row["entitlement_is_new"]),
            idempotency_receipt=str(row["idempotency_receipt"]),
        )

    @staticmethod
    def expected_entitlement_receipt(
        *,
        workspace_id: UUID,
        task_run_id: UUID,
        component_id: str = DEFAULT_ENTITLEMENT_COMPONENT,
    ) -> str:
        return entitlement_business_key(
            workspace_id=workspace_id,
            task_run_id=task_run_id,
            component_id=component_id,
        )
