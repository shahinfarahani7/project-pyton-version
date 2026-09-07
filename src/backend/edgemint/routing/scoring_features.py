from __future__ import annotations

from typing import Any

from edgemint.routing.policy import RoutingPolicy
from edgemint.routing.scarcity_cost import (
    compute_failure_affinity_bps,
    compute_scarcity_fragmentation_bps,
    parse_attempt_failures,
)


def _model_locality_formula(policy: RoutingPolicy) -> dict[str, int]:
    formulas = policy.spec["score"]["featureFormulas"]["modelLocality"]
    return {
        "loaded": int(formulas["exactModelLoadedBps"]),
        "installed": int(formulas["exactModelInstalledBps"]),
        "cached": int(formulas["verifiedLocalArtifactCacheBps"]),
        "none": int(formulas["otherwiseBps"]),
    }


def compute_model_locality_bps(
    *,
    required_model_ids: list[str],
    loaded_model_ids: list[str] | None = None,
    installed_model_ids: list[str] | None = None,
    cached_model_ids: list[str] | None = None,
    policy: RoutingPolicy | None = None,
) -> int:
    """Section 37 model locality: prefer resident required model over cold workers."""
    active = policy or RoutingPolicy.load()
    formula = _model_locality_formula(active)
    if not required_model_ids:
        return formula["none"]

    required = set(required_model_ids)
    loaded = set(loaded_model_ids or [])
    installed = set(installed_model_ids or [])
    cached = set(cached_model_ids or [])

    if required.issubset(loaded):
        return formula["loaded"]
    if required.issubset(installed):
        return formula["installed"]
    if required.issubset(cached):
        return formula["cached"]
    return formula["none"]


def compute_resource_fit_bps(
    *,
    effective_budgets: dict[str, int],
    reserved_totals: dict[str, int],
    requested_totals: dict[str, int],
) -> int:
    """Section 37 resource fit from remaining headroom after assignment (0..10000 bps)."""
    dimensions: list[int] = []
    for key in ("cpuUnits", "memoryBytes", "storageBytes"):
        effective = max(int(effective_budgets[key]), 1)
        remaining = effective - int(reserved_totals[key]) - int(requested_totals[key])
        dimensions.append(max(0, min(10_000, (remaining * 10_000) // effective)))
    return min(dimensions)


def enrich_candidate_features_bps(
    candidate: dict[str, Any],
    *,
    policy: RoutingPolicy | None = None,
) -> dict[str, int]:
    """Fill policy-controlled feature scores from structured candidate signals."""
    active = policy or RoutingPolicy.load()
    features = dict(candidate["featuresBps"])

    required_model_ids = candidate.get("requiredModelIds")
    if required_model_ids is not None:
        features["modelLocality"] = compute_model_locality_bps(
            required_model_ids=list(required_model_ids),
            loaded_model_ids=list(candidate.get("loadedModelIds") or []),
            installed_model_ids=list(candidate.get("installedModelIds") or []),
            cached_model_ids=list(candidate.get("cachedModelIds") or []),
            policy=active,
        )

    effective_budgets = candidate.get("effectiveBudgets")
    reserved_totals = candidate.get("reservedTotals")
    requested_totals = candidate.get("requestedTotals")
    if effective_budgets and reserved_totals and requested_totals:
        fit = compute_resource_fit_bps(
            effective_budgets=dict(effective_budgets),
            reserved_totals=dict(reserved_totals),
            requested_totals=dict(requested_totals),
        )
        features["predictedLatency"] = min(features.get("predictedLatency", 10_000), fit)

    task_cost_units = candidate.get("taskCostUnits")
    device_tier = candidate.get("deviceTier")
    if (
        task_cost_units is not None
        and device_tier
        and effective_budgets
        and reserved_totals
        and requested_totals
    ):
        features["scarcityCost"] = compute_scarcity_fragmentation_bps(
            task_cost_units=int(task_cost_units),
            device_tier=str(device_tier),
            effective_cpu_units=int(effective_budgets["cpuUnits"]),
            reserved_cpu_units=int(reserved_totals["cpuUnits"]),
            requested_cpu_units=int(requested_totals["cpuUnits"]),
        )
    elif "scarcityCost" not in features:
        features["scarcityCost"] = 10_000

    attempt_failures = parse_attempt_failures(candidate.get("attemptFailures"))
    worker_id = candidate.get("workerId")
    if worker_id and attempt_failures:
        affinity = compute_failure_affinity_bps(worker_id=str(worker_id), failures=attempt_failures)
        features["reliability"] = min(features.get("reliability", 10_000), affinity)

    calibration_factor_bps = candidate.get("calibrationFactorBps")
    if calibration_factor_bps is not None and int(calibration_factor_bps) != 10_000:
        base_latency = int(features.get("predictedLatency", 10_000))
        adjusted = base_latency * 10_000 // max(int(calibration_factor_bps), 1)
        features["predictedLatency"] = min(base_latency, max(0, adjusted))

    predicted_duration_ms = candidate.get("predictedDurationMs")
    deadline_budget_ms = int(candidate.get("deadlineBudgetMs") or 300_000)
    if predicted_duration_ms is not None:
        duration_ms = int(predicted_duration_ms)
        if calibration_factor_bps is not None:
            duration_ms = duration_ms * int(calibration_factor_bps) // 10_000
        latency_from_duration = max(
            0,
            min(10_000, 10_000 - (duration_ms * 10_000 // max(deadline_budget_ms, 1))),
        )
        features["predictedLatency"] = min(features.get("predictedLatency", 10_000), latency_from_duration)

    return features
