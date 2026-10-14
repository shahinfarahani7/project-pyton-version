from __future__ import annotations

from dataclasses import dataclass
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.contribution.boost import Boost
from edgemint.contribution.service import AcceptedRun, XpAwardRecord


def _boost(row: Any) -> Boost:
    return Boost(
        boost_id=UUID(str(row["id"])),
        worker_device_id=UUID(str(row["worker_device_id"])),
        idempotency_key=str(row["idempotency_key"]),
        debit_receipt_id=str(row["token_debit_receipt_id"]),
        bonus_bps=int(row["bonus_bps"]),
        activated_at=row["activated_at_utc"],
        expires_at=row["expires_at_utc"],
        task_quota=int(row["task_quota"]),
        tasks_used=int(row["tasks_used"]),
    )


_BOOSTS_FOR_DEVICE = """
    SELECT id, worker_device_id, idempotency_key, token_debit_receipt_id, bonus_bps,
           activated_at_utc, expires_at_utc, task_quota, tasks_used
    FROM public.worker_contribution_boosts
    WHERE worker_device_id = :worker_device_id
"""


@dataclass
class SqlContributionRepository:
    connection: AsyncConnection

    async def unscored_accepted_runs(self, worker_device_id: UUID) -> list[AcceptedRun]:
        rows = (
            await self.connection.execute(
                text(
                    """
                    SELECT candidate.task_run_id, candidate.id AS result_candidate_id,
                           candidate.worker_device_id, task.task_type,
                           assignment.assigned_at_utc, assignment.started_at_utc,
                           assignment.ended_at_utc
                    FROM public.result_candidates AS candidate
                    JOIN public.reward_entitlements AS entitlement
                      ON entitlement.result_candidate_id = candidate.id
                     AND entitlement.task_run_id = candidate.task_run_id
                    JOIN public.task_runs AS run
                      ON run.id = candidate.task_run_id
                     AND run.status IN ('succeeded', 'partial_succeeded')
                    JOIN public.assignments AS assignment
                      ON assignment.id = candidate.assignment_id
                     AND assignment.worker_device_id = candidate.worker_device_id
                     AND assignment.status = 'completed'
                     AND assignment.ended_at_utc IS NOT NULL
                    JOIN public.task_attempts AS attempt
                      ON attempt.id = candidate.task_attempt_id
                    JOIN public.tasks AS task
                      ON task.id = attempt.task_id
                    LEFT JOIN public.worker_contribution_xp_awards AS award
                      ON award.task_run_id = candidate.task_run_id
                    WHERE candidate.worker_device_id = :worker_device_id
                      AND candidate.status = 'accepted'
                      AND award.id IS NULL
                    ORDER BY assignment.ended_at_utc, candidate.task_run_id
                    """
                ),
                {"worker_device_id": worker_device_id},
            )
        ).mappings().all()
        return [
            AcceptedRun(
                task_run_id=UUID(str(row["task_run_id"])),
                result_candidate_id=UUID(str(row["result_candidate_id"])),
                worker_device_id=UUID(str(row["worker_device_id"])),
                task_type=str(row["task_type"]),
                assigned_at=row["assigned_at_utc"],
                started_at=row["started_at_utc"],
                completed_at=row["ended_at_utc"],
            )
            for row in rows
        ]

    async def boosts(self, worker_device_id: UUID) -> list[Boost]:
        rows = (
            await self.connection.execute(
                text(_BOOSTS_FOR_DEVICE + " ORDER BY activated_at_utc"),
                {"worker_device_id": worker_device_id},
            )
        ).mappings().all()
        return [_boost(row) for row in rows]

    async def record_award(self, award: XpAwardRecord, *, consumed_boost: Boost | None) -> bool:
        async with self.connection.begin_nested():
            inserted = (
                await self.connection.execute(
                    text(
                        """
                        INSERT INTO public.worker_contribution_xp_awards(
                          task_run_id, result_candidate_id, worker_device_id, task_type,
                          centi_xp, accepted_processing_ms, time_component, boost_id, policy_version
                        ) VALUES (
                          :task_run_id, :result_candidate_id, :worker_device_id, :task_type,
                          :centi_xp, :accepted_processing_ms, :time_component, :boost_id, :policy_version
                        )
                        ON CONFLICT ON CONSTRAINT UQ_contribution_xp_task_run DO NOTHING
                        RETURNING id
                        """
                    ),
                    {
                        "task_run_id": award.task_run_id,
                        "result_candidate_id": award.result_candidate_id,
                        "worker_device_id": award.worker_device_id,
                        "task_type": award.task_type,
                        "centi_xp": award.centi_xp,
                        "accepted_processing_ms": award.accepted_processing_ms,
                        "time_component": award.time_component,
                        "boost_id": award.boost_id,
                        "policy_version": award.policy_version,
                    },
                )
            ).scalar_one_or_none()
            if inserted is None:
                return False
            if consumed_boost is not None:
                updated = (
                    await self.connection.execute(
                        text(
                            """
                            UPDATE public.worker_contribution_boosts
                            SET tasks_used = tasks_used + 1
                            WHERE id = :boost_id AND tasks_used < task_quota
                            RETURNING id
                            """
                        ),
                        {"boost_id": consumed_boost.boost_id},
                    )
                ).scalar_one_or_none()
                if updated is None:
                    raise RuntimeError("boost quota consumed concurrently; award retried on next scoring")
        return True

    async def awards(self, worker_device_id: UUID) -> list[XpAwardRecord]:
        rows = (
            await self.connection.execute(
                text(
                    """
                    SELECT task_run_id, result_candidate_id, worker_device_id, task_type, centi_xp,
                           accepted_processing_ms, time_component, boost_id, policy_version
                    FROM public.worker_contribution_xp_awards
                    WHERE worker_device_id = :worker_device_id
                    """
                ),
                {"worker_device_id": worker_device_id},
            )
        ).mappings().all()
        return [
            XpAwardRecord(
                task_run_id=UUID(str(row["task_run_id"])),
                result_candidate_id=UUID(str(row["result_candidate_id"])),
                worker_device_id=UUID(str(row["worker_device_id"])),
                task_type=str(row["task_type"]),
                centi_xp=int(row["centi_xp"]),
                accepted_processing_ms=(
                    None if row["accepted_processing_ms"] is None else int(row["accepted_processing_ms"])
                ),
                time_component=str(row["time_component"]),
                boost_id=None if row["boost_id"] is None else UUID(str(row["boost_id"])),
                policy_version=str(row["policy_version"]),
            )
            for row in rows
        ]

    async def boost_by_idempotency_key(self, worker_device_id: UUID, key: str) -> Boost | None:
        row = (
            await self.connection.execute(
                text(_BOOSTS_FOR_DEVICE + " AND idempotency_key = :key"),
                {"worker_device_id": worker_device_id, "key": key},
            )
        ).mappings().first()
        return None if row is None else _boost(row)

    async def lock_boosts(self, worker_device_id: UUID) -> None:
        await self.connection.execute(
            text("SELECT pg_advisory_xact_lock(hashtextextended(:lock_key, 0))"),
            {"lock_key": f"contribution-boost:{worker_device_id}"},
        )

    async def insert_boost(self, boost: Boost) -> bool:
        inserted = (
            await self.connection.execute(
                text(
                    """
                    INSERT INTO public.worker_contribution_boosts(
                      id, worker_device_id, idempotency_key, token_debit_receipt_id, bonus_bps,
                      activated_at_utc, expires_at_utc, task_quota, tasks_used
                    ) VALUES (
                      :id, :worker_device_id, :idempotency_key, :debit, :bonus_bps,
                      :activated_at, :expires_at, :task_quota, 0
                    )
                    ON CONFLICT ON CONSTRAINT UQ_contribution_boost_idempotency DO NOTHING
                    RETURNING id
                    """
                ),
                {
                    "id": boost.boost_id,
                    "worker_device_id": boost.worker_device_id,
                    "idempotency_key": boost.idempotency_key,
                    "debit": boost.debit_receipt_id,
                    "bonus_bps": boost.bonus_bps,
                    "activated_at": boost.activated_at,
                    "expires_at": boost.expires_at,
                    "task_quota": boost.task_quota,
                },
            )
        ).scalar_one_or_none()
        return inserted is not None
