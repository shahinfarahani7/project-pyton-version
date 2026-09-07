from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from edgemint.routing.artifact_affinity import artifact_blocks_worker, blocked_artifact_digests_from_failures
from edgemint.routing.policy import RoutingPolicy
from edgemint.routing.resource_budget import ResourceClassTotals, resource_class_budget_reasons
from edgemint.routing.runtime_compatibility import runtime_incompatibility_reasons
from edgemint.routing.scarcity_cost import failure_affinity_blocks_worker, parse_attempt_failures


def evaluate_hard_eligibility(
    candidate: dict[str, Any],
    *,
    policy: RoutingPolicy | None = None,
    bypass: bool = False,
) -> list[str]:
    """Section 10 hard filters applied before worker scoring."""
    if bypass:
        return []

    active = policy or RoutingPolicy.load()
    rules = active.eligibility
    reasons: list[str] = []
    features = candidate["featuresBps"]

    if candidate["heartbeatAgeSeconds"] > rules["heartbeatMaximumAgeSeconds"]:
        reasons.append("STALE_HEARTBEAT")
    if rules["requireAvailableStatus"] and not candidate.get("available", True):
        reasons.append("WORKER_UNAVAILABLE")
    if features["trust"] < rules["minimumTrustMilli"] * 10:
        reasons.append("TRUST_TOO_LOW")
    if rules["requireAttestationForPaidTasks"] and not candidate.get("attested", False):
        reasons.append("ATTESTATION_REQUIRED")
    if rules["requireCurrentConsent"] and not candidate.get("consentCurrent", False):
        reasons.append("CONSENT_REQUIRED")
    if candidate.get("requireCpuEnforcementCertification", False) and not candidate.get(
        "cpuEnforcementCertified", False
    ):
        reasons.append("CPU_ENFORCEMENT_UNCERTIFIED")
    if candidate["batteryPercent"] < rules["minimumBatteryPercent"]:
        reasons.append("BATTERY_TOO_LOW")
    if candidate["thermalState"] in rules["disallowedThermalStates"]:
        reasons.append("THERMAL_BLOCK")
    if rules["respectCustomerRegion"] and not candidate.get("regionAllowed", True):
        reasons.append("REGION_NOT_ALLOWED")
    if rules["respectWorkerNetworkPolicy"] and not candidate.get("networkPolicyAllowed", True):
        reasons.append("NETWORK_POLICY_BLOCKED")
    if rules["requireModelDigestMatch"] and not candidate.get("modelDigestMatch", True):
        reasons.append("MODEL_DIGEST_MISMATCH")
    if not candidate.get("modelAvailable", True):
        reasons.append("MODEL_UNAVAILABLE")
    if rules["requireRuntimeAbiMatch"] and not candidate.get("runtimeAbiMatch", True):
        reasons.append("RUNTIME_ABI_MISMATCH")

    required_free_storage = candidate.get("requiredFreeStorageBytes")
    free_storage_bytes = candidate.get("freeStorageBytes")
    if required_free_storage is not None and free_storage_bytes is not None:
        if int(free_storage_bytes) < int(required_free_storage):
            reasons.append("INSUFFICIENT_STORAGE")

    if candidate.get("cooldownActive", False):
        reasons.append("FAILURE_COOLDOWN")
    cooldown_until = candidate.get("cooldownUntilUtc")
    if cooldown_until is not None:
        until = cooldown_until if isinstance(cooldown_until, datetime) else datetime.fromisoformat(
            str(cooldown_until).replace("Z", "+00:00")
        )
        if until.tzinfo is None:
            until = until.replace(tzinfo=UTC)
        if until > datetime.now(UTC):
            reasons.append("FAILURE_COOLDOWN")

    worker_id = candidate.get("workerId")
    attempt_failures_raw = candidate.get("attemptFailures")
    failures = parse_attempt_failures(attempt_failures_raw) if attempt_failures_raw else []
    if worker_id and failures:
        if failure_affinity_blocks_worker(worker_id=str(worker_id), failures=failures):
            reasons.append("FAILURE_AFFINITY")

    task_failures_raw = candidate.get("taskRunFailures")
    if task_failures_raw:
        blocked_artifacts = blocked_artifact_digests_from_failures(
            parse_attempt_failures(task_failures_raw)
        )
        if artifact_blocks_worker(
            model_version_id=candidate.get("modelVersionId"),
            blocked_artifact_digests=blocked_artifacts,
        ):
            reasons.append("ARTIFACT_BLOCKED")

    if candidate.get("assignmentSafetyBlocked", False) or candidate.get("quarantined", False):
        reasons.append("ASSIGNMENT_SAFETY_BLOCKED")

    effective_budgets = candidate.get("effectiveBudgets")
    reserved_totals = candidate.get("reservedTotals")
    requested_totals = candidate.get("requestedTotals")
    if effective_budgets and reserved_totals and requested_totals:
        from edgemint.routing.resource_budget import EffectiveResourceBudgets

        reasons.extend(
            resource_class_budget_reasons(
                effective=EffectiveResourceBudgets(
                    cpu_units=int(effective_budgets["cpuUnits"]),
                    memory_bytes=int(effective_budgets["memoryBytes"]),
                    storage_bytes=int(effective_budgets["storageBytes"]),
                ),
                reserved=ResourceClassTotals(
                    cpu_units=int(reserved_totals["cpuUnits"]),
                    memory_bytes=int(reserved_totals["memoryBytes"]),
                    storage_bytes=int(reserved_totals["storageBytes"]),
                ),
                requested=ResourceClassTotals(
                    cpu_units=int(requested_totals["cpuUnits"]),
                    memory_bytes=int(requested_totals["memoryBytes"]),
                    storage_bytes=int(requested_totals["storageBytes"]),
                ),
            )
        )

    task_runtime_class = candidate.get("taskRuntimeClass")
    worker_runtime_classes = candidate.get("workerRuntimeClasses")
    if task_runtime_class and worker_runtime_classes is not None:
        reasons.extend(
            runtime_incompatibility_reasons(
                worker_runtime_classes=list(worker_runtime_classes),
                task_runtime_class=str(task_runtime_class),
                device_tier=candidate.get("deviceTier"),
                active_runtime_classes=candidate.get("activeRuntimeClasses"),
            )
        )

    return reasons


def partition_candidates_by_hard_eligibility(
    candidates: list[dict[str, Any]],
    *,
    policy: RoutingPolicy | None = None,
    bypass: bool = False,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Split worker candidates into eligible (scorable) and ineligible buckets."""
    eligible: list[dict[str, Any]] = []
    ineligible: list[dict[str, Any]] = []
    for item in candidates:
        payload = dict(item["input"])
        if "workerId" in item:
            payload["workerId"] = item["workerId"]
        reasons = evaluate_hard_eligibility(payload, policy=policy, bypass=bypass)
        if reasons:
            ineligible.append({**item, "ineligibilityReasons": reasons})
        else:
            eligible.append(item)
    return eligible, ineligible
