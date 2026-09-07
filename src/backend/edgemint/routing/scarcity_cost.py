from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime

TIER_PREMIUM_BPS: dict[str, int] = {
    "T4": 10_000,
    "T3": 7_500,
    "T2": 5_000,
    "T1": 2_500,
}


def compute_scarcity_fragmentation_bps(
    *,
    task_cost_units: int,
    device_tier: str,
    effective_cpu_units: int,
    reserved_cpu_units: int,
    requested_cpu_units: int,
) -> int:
    """Section 37 scarcity/fragmentation cost (formula v1).

    Cheap tasks on premium workers receive a lower score component so scarce T4
    capacity is not wasted on low-intensity work. Deterministic integer math only.
    """
    effective = max(effective_cpu_units, 1)
    projected = reserved_cpu_units + requested_cpu_units
    utilization_bps = min(10_000, (projected * 10_000) // effective)
    task_intensity_bps = min(10_000, (max(task_cost_units, 0) * 10_000) // effective)
    tier_premium_bps = TIER_PREMIUM_BPS.get(device_tier.upper(), 5_000)
    mismatch_bps = max(0, tier_premium_bps - task_intensity_bps)
    fragmentation_bps = (mismatch_bps * utilization_bps) // 10_000
    return max(0, 10_000 - fragmentation_bps)


@dataclass(frozen=True, slots=True)
class AttemptWorkerFailure:
    worker_id: str
    failure_code: str
    observed_at_utc: datetime
    cooldown_until_utc: datetime | None = None
    runtime_class: str | None = None
    model_version_id: str | None = None


def compute_failure_affinity_bps(
    *,
    worker_id: str,
    failures: list[AttemptWorkerFailure],
    now: datetime | None = None,
) -> int:
    """Section 45: deprioritize workers with recent failures on the same attempt."""
    clock = now or datetime.now(UTC)
    penalty = 10_000
    for failure in failures:
        if failure.worker_id != worker_id:
            continue
        if failure.cooldown_until_utc is not None:
            cooldown = failure.cooldown_until_utc
            if cooldown.tzinfo is None:
                cooldown = cooldown.replace(tzinfo=UTC)
            if cooldown > clock:
                return 0
        penalty = min(penalty, 3_000)
    return penalty


def failure_affinity_blocks_worker(
    *,
    worker_id: str,
    failures: list[AttemptWorkerFailure],
    now: datetime | None = None,
) -> bool:
    clock = now or datetime.now(UTC)
    for failure in failures:
        if failure.worker_id != worker_id:
            continue
        if failure.cooldown_until_utc is None:
            continue
        cooldown = failure.cooldown_until_utc
        if cooldown.tzinfo is None:
            cooldown = cooldown.replace(tzinfo=UTC)
        if cooldown > clock:
            return True
    return False


def parse_attempt_failures(raw: object) -> list[AttemptWorkerFailure]:
    if not raw:
        return []
    failures: list[AttemptWorkerFailure] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        observed_raw = item.get("observedAtUtc") or item.get("observed_at_utc")
        cooldown_raw = item.get("cooldownUntilUtc") or item.get("cooldown_until_utc")
        observed = (
            observed_raw
            if isinstance(observed_raw, datetime)
            else datetime.fromisoformat(str(observed_raw).replace("Z", "+00:00"))
        )
        cooldown = None
        if cooldown_raw is not None:
            cooldown = (
                cooldown_raw
                if isinstance(cooldown_raw, datetime)
                else datetime.fromisoformat(str(cooldown_raw).replace("Z", "+00:00"))
            )
        failures.append(
            AttemptWorkerFailure(
                worker_id=str(item["workerId"]),
                failure_code=str(item.get("failureCode", "UNKNOWN")),
                observed_at_utc=observed,
                cooldown_until_utc=cooldown,
                runtime_class=item.get("runtimeClass"),
                model_version_id=item.get("modelVersionId"),
            )
        )
    return failures
