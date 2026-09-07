from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.routing.scarcity_cost import AttemptWorkerFailure


@dataclass(frozen=True, slots=True)
class FailureAffinityService:
    default_cooldown_seconds: int = 300

    async def record_failure(
        self,
        connection: AsyncConnection,
        *,
        task_attempt_id: UUID,
        worker_device_id: UUID,
        failure_code: str,
        runtime_class: str | None = None,
        model_version_id: str | None = None,
        cooldown_seconds: int | None = None,
        observed_at: datetime | None = None,
    ) -> AttemptWorkerFailure:
        now = observed_at or datetime.now(UTC)
        cooldown = now + timedelta(seconds=cooldown_seconds or self.default_cooldown_seconds)
        await connection.execute(
            text(
                """
                INSERT INTO public.attempt_worker_failures(
                    task_attempt_id, worker_device_id, runtime_class, model_version_id,
                    failure_code, observed_at_utc, cooldown_until_utc
                )
                VALUES (
                    :task_attempt_id, :worker_device_id, :runtime_class, :model_version_id,
                    :failure_code, :observed_at_utc, :cooldown_until_utc
                )
                """
            ),
            {
                "task_attempt_id": task_attempt_id,
                "worker_device_id": worker_device_id,
                "runtime_class": runtime_class,
                "model_version_id": model_version_id,
                "failure_code": failure_code,
                "observed_at_utc": now,
                "cooldown_until_utc": cooldown,
            },
        )
        return AttemptWorkerFailure(
            worker_id=str(worker_device_id),
            failure_code=failure_code,
            observed_at_utc=now,
            cooldown_until_utc=cooldown,
            runtime_class=runtime_class,
            model_version_id=model_version_id,
        )

    async def load_attempt_failures(
        self,
        connection: AsyncConnection,
        *,
        task_attempt_id: UUID,
    ) -> list[dict[str, Any]]:
        rows = (
            await connection.execute(
                text(
                    """
                    SELECT worker_device_id, runtime_class, model_version_id,
                           failure_code, observed_at_utc, cooldown_until_utc
                    FROM public.attempt_worker_failures
                    WHERE task_attempt_id = :task_attempt_id
                    ORDER BY observed_at_utc DESC
                    """
                ),
                {"task_attempt_id": task_attempt_id},
            )
        ).mappings().all()
        return [
            {
                "workerId": str(row["worker_device_id"]),
                "failureCode": str(row["failure_code"]),
                "observedAtUtc": row["observed_at_utc"],
                "cooldownUntilUtc": row["cooldown_until_utc"],
                "runtimeClass": row["runtime_class"],
                "modelVersionId": row["model_version_id"],
            }
            for row in rows
        ]
