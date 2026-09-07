from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from enum import StrEnum
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.tasks.errors import task_error
from edgemint.routing.task_run_budget import load_task_run_budget_limits


class TaskRunStatus(StrEnum):
    PENDING = "pending"
    ROUTING = "routing"
    QUEUED = "queued"
    EXECUTING = "executing"
    VALIDATING = "validating"
    SUCCEEDED = "succeeded"
    PARTIAL_SUCCEEDED = "partial_succeeded"
    FAILED = "failed"
    CANCELLED = "cancelled"
    DEADLINE_EXPIRED = "deadline_expired"


TERMINAL_STATUSES = frozenset(
    {
        TaskRunStatus.SUCCEEDED,
        TaskRunStatus.PARTIAL_SUCCEEDED,
        TaskRunStatus.FAILED,
        TaskRunStatus.CANCELLED,
        TaskRunStatus.DEADLINE_EXPIRED,
    }
)

NON_TERMINAL_STATUSES = frozenset(
    status for status in TaskRunStatus if status not in TERMINAL_STATUSES
)


def compute_input_digest(
    *,
    inline_text: str | None,
    parameters_json: str,
    input_file_id: UUID | None,
) -> str:
    payload = json.dumps(
        {
            "inlineText": inline_text or "",
            "parameters": json.loads(parameters_json),
            "inputFileId": str(input_file_id) if input_file_id else None,
        },
        sort_keys=True,
        separators=(",", ":"),
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


@dataclass(frozen=True, slots=True)
class TaskRunTerminalCommit:
    task_run_id: UUID
    terminal_status: TaskRunStatus
    terminal_outcome: str
    committed: bool


class TaskRunService:
    """TaskRun lifecycle helpers (v2 §20): distinct from TaskRevision."""

    async def create_for_admitted_task(
        self,
        connection: AsyncConnection,
        *,
        workspace_id: UUID,
        task_id: UUID,
        task_revision_id: UUID,
        client_request_key: str,
        input_digest: str,
        status: TaskRunStatus = TaskRunStatus.QUEUED,
    ) -> UUID:
        limits = load_task_run_budget_limits()
        task_run_id = (
            await connection.execute(
                text(
                    """
                    INSERT INTO public.task_runs(
                        workspace_id, task_id, task_revision_id,
                        client_request_key, input_digest, status,
                        max_attempts, max_total_assignments, max_cloud_fallbacks
                    )
                    VALUES (
                        :workspace_id, :task_id, :task_revision_id,
                        :client_request_key, :input_digest, :status,
                        :max_attempts, :max_total_assignments, :max_cloud_fallbacks
                    )
                    RETURNING id
                    """
                ),
                {
                    "workspace_id": workspace_id,
                    "task_id": task_id,
                    "task_revision_id": task_revision_id,
                    "client_request_key": client_request_key,
                    "input_digest": input_digest,
                    "status": str(status),
                    "max_attempts": limits.max_attempts,
                    "max_total_assignments": limits.max_total_assignments,
                    "max_cloud_fallbacks": limits.max_cloud_fallbacks,
                },
            )
        ).scalar_one()
        return UUID(str(task_run_id))

    async def cancel_open_runs_for_task(
        self,
        connection: AsyncConnection,
        *,
        workspace_id: UUID,
        task_id: UUID,
        terminal_outcome: str = "client_cancel",
    ) -> list[TaskRunTerminalCommit]:
        rows = (
            await connection.execute(
                text(
                    """
                    SELECT id
                    FROM public.task_runs
                    WHERE workspace_id = :workspace_id
                      AND task_id = :task_id
                      AND terminal_committed_at_utc IS NULL
                    """
                ),
                {"workspace_id": workspace_id, "task_id": task_id},
            )
        ).scalars().all()
        commits: list[TaskRunTerminalCommit] = []
        for task_run_id in rows:
            commits.append(
                await self.commit_terminal(
                    connection,
                    task_run_id=UUID(str(task_run_id)),
                    terminal_status=TaskRunStatus.CANCELLED,
                    terminal_outcome=terminal_outcome,
                )
            )
        return commits

    async def commit_terminal(
        self,
        connection: AsyncConnection,
        *,
        task_run_id: UUID,
        terminal_status: TaskRunStatus,
        terminal_outcome: str,
    ) -> TaskRunTerminalCommit:
        if terminal_status not in TERMINAL_STATUSES:
            raise task_error(
                "INPUT_SCHEMA_INVALID",
                detail=f"non-terminal status: {terminal_status}",
            )
        committed = (
            await connection.execute(
                text(
                    "SELECT public.commit_task_run_terminal("
                    ":task_run_id, :terminal_status, :terminal_outcome)"
                ),
                {
                    "task_run_id": task_run_id,
                    "terminal_status": str(terminal_status),
                    "terminal_outcome": terminal_outcome,
                },
            )
        ).scalar_one()
        return TaskRunTerminalCommit(
            task_run_id=task_run_id,
            terminal_status=terminal_status,
            terminal_outcome=terminal_outcome,
            committed=bool(committed),
        )

    async def get_status(
        self,
        connection: AsyncConnection,
        *,
        task_run_id: UUID,
    ) -> TaskRunStatus | None:
        row = (
            await connection.execute(
                text("SELECT status FROM public.task_runs WHERE id = :id"),
                {"id": task_run_id},
            )
        ).scalar_one_or_none()
        return TaskRunStatus(str(row)) if row is not None else None
