"""Operational queue consumer: claim attempt -> scheduler stack -> atomic assignment."""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.building_blocks.database import transaction
from edgemint.building_blocks.settings import Settings, get_settings
from edgemint.governance.runtime_activation import assert_runtime_activation_gate_open
from edgemint.routing.policy import RoutingPolicy
from edgemint.routing.service import RouterService
from edgemint.routing.task_run_budget import TaskRunBudgetUsage

logger = logging.getLogger(__name__)


@dataclass(slots=True)
class SchedulerConsumer:
    router: RouterService = field(default_factory=RouterService)
    settings: Settings = field(default_factory=get_settings)
    router_instance_id: str = "scheduler-consumer"
    claim_seconds: int = 30
    candidate_window: int = 200

    async def load_attempt_context(
        self,
        connection: AsyncConnection,
        *,
        task_attempt_id: UUID,
    ) -> dict[str, Any] | None:
        row = (
            await connection.execute(
                text(
                    """
                    SELECT attempt.id AS task_attempt_id,
                           attempt.task_run_id,
                           task.public_id AS task_public_id,
                           task.submitted_at_utc,
                           task.task_type,
                           COALESCE(
                               (
                                   SELECT count(*)
                                   FROM public.assignments AS prior
                                   WHERE prior.task_attempt_id = attempt.id
                               ),
                               0
                           ) AS prior_assignments,
                           COALESCE(run.assignment_count, 0) AS task_run_assignment_count,
                           COALESCE(run.attempt_count, 1) AS task_run_attempt_count,
                           COALESCE(run.cloud_fallback_count, 0) AS task_run_cloud_fallback_count
                    FROM public.task_attempts AS attempt
                    JOIN public.tasks AS task
                      ON task.id = attempt.task_id
                     AND task.workspace_id = attempt.workspace_id
                    LEFT JOIN public.task_runs AS run
                      ON run.id = attempt.task_run_id
                    WHERE attempt.id = :task_attempt_id
                    """
                ),
                {"task_attempt_id": task_attempt_id},
            )
        ).mappings().first()
        return dict(row) if row is not None else None

    async def load_candidates_for_attempt(
        self,
        connection: AsyncConnection,
        *,
        task_attempt_id: UUID,
    ) -> list[dict[str, Any]]:
        rows = (
            await connection.execute(
                text(
                    """
                    SELECT worker.id AS worker_id,
                           device.id AS worker_device_id,
                           worker.trust_bps,
                           device.device_tier,
                           heartbeat.received_at_utc,
                           heartbeat.battery_bps,
                           heartbeat.thermal_state,
                           heartbeat.network_type,
                           heartbeat.charging,
                           heartbeat.free_storage_bytes,
                           heartbeat.telemetry_json,
                           revision.minimum_free_storage_bytes,
                           revision.model_version_id
                    FROM public.task_attempts AS attempt
                    JOIN public.tasks AS task
                      ON task.id = attempt.task_id
                     AND task.workspace_id = attempt.workspace_id
                    JOIN public.task_revisions AS revision
                      ON revision.id = task.current_revision_id
                     AND revision.workspace_id = task.workspace_id
                    JOIN public.workers AS worker
                      ON worker.status = 'active'
                    JOIN public.worker_devices AS device
                      ON device.worker_id = worker.id
                     AND device.status = 'active'
                    JOIN public.worker_preferences AS preference
                      ON preference.worker_id = worker.id
                    JOIN LATERAL (
                        SELECT heartbeat_inner.*
                        FROM public.worker_heartbeats AS heartbeat_inner
                        WHERE heartbeat_inner.worker_device_id = device.id
                        ORDER BY heartbeat_inner.received_at_utc DESC,
                                 heartbeat_inner.sequence_number DESC
                        LIMIT 1
                    ) AS heartbeat ON true
                    WHERE attempt.id = :task_attempt_id
                      AND preference.availability = 'available'
                      AND device.attestation_status = 'verified'
                      AND device.attestation_expires_at_utc > CURRENT_TIMESTAMP
                      AND EXISTS (
                        SELECT 1
                        FROM public.worker_consents AS consent
                        WHERE consent.worker_id = worker.id
                          AND consent.withdrawn_at_utc IS NULL
                      )
                    ORDER BY worker.trust_bps DESC, worker.id, device.id
                    LIMIT 200
                    """
                ),
                {"task_attempt_id": task_attempt_id},
            )
        ).mappings().all()

        candidates: list[dict[str, Any]] = []
        now = datetime.now(UTC)
        for row in rows:
            received_at = row["received_at_utc"]
            if received_at is not None and received_at.tzinfo is None:
                received_at = received_at.replace(tzinfo=UTC)
            heartbeat_age = max(
                0,
                int((now - received_at).total_seconds()) if received_at is not None else 999,
            )
            telemetry = row.get("telemetry_json") or {}
            if isinstance(telemetry, str):
                import json

                telemetry = json.loads(telemetry)
            loaded_model_ids = []
            if isinstance(telemetry, dict):
                loaded_model_ids = list(telemetry.get("loadedModelIds") or [])
            battery_percent = int(int(row["battery_bps"] or 0) // 100)
            candidates.append(
                {
                    "workerId": str(row["worker_id"]),
                    "workerDeviceId": str(row["worker_device_id"]),
                    "input": {
                        "workerId": str(row["worker_id"]),
                        "featuresBps": {
                            "modelLocality": 10_000,
                            "trust": int(row["trust_bps"] or 0),
                            "predictedLatency": 10_000,
                            "batteryCharging": 10_000 if row["charging"] else 0,
                            "network": 10_000 if row["network_type"] != "offline" else 0,
                            "regionalCompliance": 10_000,
                            "priceEfficiency": 10_000,
                            "reliability": 10_000,
                        },
                        "heartbeatAgeSeconds": heartbeat_age,
                        "batteryPercent": battery_percent,
                        "thermalState": str(row["thermal_state"] or "nominal"),
                        "attested": True,
                        "consentCurrent": True,
                        "modelDigestMatch": True,
                        "modelAvailable": True,
                        "runtimeAbiMatch": True,
                        "regionAllowed": True,
                        "networkPolicyAllowed": row["network_type"] != "offline",
                        "available": True,
                        "freeStorageBytes": int(row["free_storage_bytes"] or 0),
                        "requiredFreeStorageBytes": int(row["minimum_free_storage_bytes"] or 0),
                        "loadedModelIds": loaded_model_ids,
                        "deviceTier": str(row["device_tier"] or "T2"),
                    },
                }
            )
        return candidates

    async def process_once(
        self,
        connection: AsyncConnection,
    ) -> dict[str, Any] | None:
        await assert_runtime_activation_gate_open(connection, settings=self.settings)

        attempt_id = await self.router.select_next_attempt(
            connection,
            router_instance_id=self.router_instance_id,
            claim_seconds=self.claim_seconds,
            candidate_window=self.candidate_window,
        )
        if attempt_id is None:
            return None

        context = await self.load_attempt_context(connection, task_attempt_id=attempt_id)
        if context is None:
            return None

        candidates = await self.load_candidates_for_attempt(
            connection,
            task_attempt_id=attempt_id,
        )
        if not candidates:
            return {
                "attemptId": str(attempt_id),
                "status": "no_candidates",
            }

        submitted_at = context["submitted_at_utc"]
        if submitted_at is not None and submitted_at.tzinfo is None:
            submitted_at = submitted_at.replace(tzinfo=UTC)
        edge_wait_seconds = (
            max(0.0, (datetime.now(UTC) - submitted_at).total_seconds())
            if submitted_at is not None
            else 0.0
        )
        usage = TaskRunBudgetUsage(
            attempt_count=int(context["task_run_attempt_count"]),
            assignment_count=int(context["task_run_assignment_count"]),
            cloud_fallback_count=int(context["task_run_cloud_fallback_count"]),
        )
        body = await self.router.assign_attempt_with_scheduler_stack(
            connection,
            task_attempt_id=attempt_id,
            task_id=str(context["task_public_id"]),
            router_epoch=int(self.router.policy.spec.get("routerEpoch", 0)),
            router_instance_id=self.router_instance_id,
            candidates=candidates,
            prior_assignments=int(context["prior_assignments"]),
            edge_wait_seconds=edge_wait_seconds,
            task_run_usage=usage,
        )
        return {
            "attemptId": str(attempt_id),
            "status": "assigned",
            **body,
        }

    async def drain_once(self, *, max_assignments: int = 1) -> list[dict[str, Any]]:
        results: list[dict[str, Any]] = []
        async with transaction(isolation="SERIALIZABLE") as connection:
            for _ in range(max_assignments):
                try:
                    outcome = await self.process_once(connection)
                except Exception:
                    logger.exception("scheduler consumer iteration failed")
                    break
                if outcome is None:
                    break
                results.append(outcome)
                if outcome.get("status") != "assigned":
                    break
        return results


def default_scheduler_consumer(*, policy: RoutingPolicy | None = None) -> SchedulerConsumer:
    router = RouterService(policy=policy or RoutingPolicy.load())
    instance_id = f"{router.settings.service_name or 'router'}-consumer"
    return SchedulerConsumer(router=router, router_instance_id=instance_id)
