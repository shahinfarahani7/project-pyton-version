from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.routing.resource_budget import contribution_budget_multiplier_bps
from edgemint.workers.consent_transitions import ConsentTransitionPlan
from edgemint.workers.resource_policy import (
    CpuEnforcementProfile,
    load_active_user_resource_policy,
)


def cpu_usage_bps_from_units(cpu_units: int) -> int:
    """Architecture §16.1: 100 cpuUnits == 10000 bps on the same time basis."""
    if cpu_units < 0:
        raise ValueError("cpu_units must be non-negative")
    return min(10_000, cpu_units * 100)


def approved_cpu_ceiling_bps(*, approved_percent: int, device_cpu_units: int) -> int:
    effective_units = (
        device_cpu_units * contribution_budget_multiplier_bps(approved_percent=approved_percent)
    ) // 10_000
    return cpu_usage_bps_from_units(effective_units)


def burst_ceiling_bps(*, approved_ceiling_bps: int, tolerated_burst_bps: int) -> int:
    return min(10_000, approved_ceiling_bps + tolerated_burst_bps)


def load_cpu_enforcement_profile() -> CpuEnforcementProfile:
    policy = load_active_user_resource_policy()
    if policy.spec.cpuEnforcement is None:
        raise ValueError("cpuEnforcement profile missing from active policy")
    return policy.spec.cpuEnforcement


def evaluate_windowed_cpu_sample(
    *,
    observed_cpu_usage_bps: int,
    approved_ceiling_bps: int,
    profile: CpuEnforcementProfile,
) -> tuple[bool, str | None]:
    if observed_cpu_usage_bps < 0 or observed_cpu_usage_bps > 10_000:
        return False, "CPU_SAMPLE_INVALID"
    ceiling = burst_ceiling_bps(
        approved_ceiling_bps=approved_ceiling_bps,
        tolerated_burst_bps=profile.toleratedBurstBps,
    )
    if observed_cpu_usage_bps > ceiling:
        return False, "CPU_BUDGET_EXCEEDED"
    return True, None


def consent_transition_stop_deadline_ms(plan: ConsentTransitionPlan) -> int | None:
    if plan.revoke_new_work_immediately or plan.stop_new_stages_above_limit:
        return load_cpu_enforcement_profile().controlStopReactionBoundMs
    return None


@dataclass(frozen=True, slots=True)
class CpuEnforcementCertification:
    worker_device_id: UUID
    policy_ref: str
    approved_percent: int
    contribution_mode_id: str
    measurement_window_ms: int
    covered_process_scope: str
    tolerated_burst_bps: int
    control_stop_reaction_bound_ms: int
    enforcement_mechanism: str
    last_observed_cpu_usage_bps: int | None


class WorkerCpuEnforcementService:
    async def sync_from_heartbeat(
        self,
        connection: AsyncConnection,
        *,
        worker_device_id: UUID,
        contribution_mode_id: str,
        approved_percent: int,
        observed_cpu_usage_bps: int | None,
        snapshot_sequence: int,
    ) -> UUID:
        policy = load_active_user_resource_policy()
        profile = load_cpu_enforcement_profile()
        policy_ref = f"UserResourcePolicy/{policy.name}@{policy.version}"
        certification_id = (
            await connection.execute(
                text(
                    """
                    SELECT public.upsert_worker_cpu_enforcement_certification(
                        :worker_device_id, :policy_ref, :measurement_window_ms,
                        :covered_process_scope, :tolerated_burst_bps,
                        :control_stop_reaction_bound_ms, :enforcement_mechanism,
                        :approved_percent, :contribution_mode_id,
                        :last_observed_cpu_usage_bps, :snapshot_sequence
                    )
                    """
                ),
                {
                    "worker_device_id": worker_device_id,
                    "policy_ref": policy_ref,
                    "measurement_window_ms": profile.measurementWindowMs,
                    "covered_process_scope": profile.coveredProcessScope,
                    "tolerated_burst_bps": profile.toleratedBurstBps,
                    "control_stop_reaction_bound_ms": profile.controlStopReactionBoundMs,
                    "enforcement_mechanism": profile.enforcementMechanism,
                    "approved_percent": approved_percent,
                    "contribution_mode_id": contribution_mode_id,
                    "last_observed_cpu_usage_bps": observed_cpu_usage_bps,
                    "snapshot_sequence": snapshot_sequence,
                },
            )
        ).scalar_one()
        return UUID(str(certification_id))

    async def is_certified(
        self,
        connection: AsyncConnection,
        *,
        worker_device_id: UUID,
    ) -> bool:
        policy = load_active_user_resource_policy()
        expected_ref = f"UserResourcePolicy/{policy.name}@{policy.version}"
        row = (
            await connection.execute(
                text(
                    """
                    SELECT 1
                    FROM public.worker_cpu_enforcement_certifications
                    WHERE worker_device_id = :worker_device_id
                      AND policy_ref = :policy_ref
                    LIMIT 1
                    """
                ),
                {
                    "worker_device_id": worker_device_id,
                    "policy_ref": expected_ref,
                },
            )
        ).first()
        return row is not None

    async def load_certification(
        self,
        connection: AsyncConnection,
        *,
        worker_device_id: UUID,
    ) -> CpuEnforcementCertification | None:
        row = (
            await connection.execute(
                text(
                    """
                    SELECT worker_device_id, policy_ref, approved_percent,
                           contribution_mode_id, measurement_window_ms,
                           covered_process_scope, tolerated_burst_bps,
                           control_stop_reaction_bound_ms, enforcement_mechanism,
                           last_observed_cpu_usage_bps
                    FROM public.worker_cpu_enforcement_certifications
                    WHERE worker_device_id = :worker_device_id
                    """
                ),
                {"worker_device_id": worker_device_id},
            )
        ).mappings().first()
        if row is None:
            return None
        return CpuEnforcementCertification(
            worker_device_id=UUID(str(row["worker_device_id"])),
            policy_ref=str(row["policy_ref"]),
            approved_percent=int(row["approved_percent"]),
            contribution_mode_id=str(row["contribution_mode_id"]),
            measurement_window_ms=int(row["measurement_window_ms"]),
            covered_process_scope=str(row["covered_process_scope"]),
            tolerated_burst_bps=int(row["tolerated_burst_bps"]),
            control_stop_reaction_bound_ms=int(row["control_stop_reaction_bound_ms"]),
            enforcement_mechanism=str(row["enforcement_mechanism"]),
            last_observed_cpu_usage_bps=(
                int(row["last_observed_cpu_usage_bps"])
                if row["last_observed_cpu_usage_bps"] is not None
                else None
            ),
        )
