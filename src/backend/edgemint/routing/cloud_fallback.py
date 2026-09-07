from __future__ import annotations

from dataclasses import dataclass

from edgemint.security.tenant_data_trust import evaluate_cloud_fallback_trust
from edgemint.routing.policy import RoutingPolicy
from edgemint.routing.routing_audit import policy_hash
from edgemint.routing.task_run_budget import (
    TaskRunBudgetLimits,
    TaskRunBudgetUsage,
    cloud_fallback_budget_permitted,
)


@dataclass(frozen=True, slots=True)
class CloudFallbackDecision:
    permitted: bool
    reason: str
    edgeWaitSeconds: float
    cloudAfterSeconds: int
    policyHash: str


def evaluate_cloud_fallback(
    *,
    edge_wait_seconds: float,
    policy: RoutingPolicy | None = None,
    customer_allows_cloud: bool = True,
    region_allows_cloud: bool = True,
    cost_cap_remaining_micros: int | None = None,
    execution_policy: str = "edge_preferred",
    data_region: str = "eu-central",
    cloud_region: str = "eu-central",
    data_owner_consent_granted: bool = True,
    task_run_usage: TaskRunBudgetUsage | None = None,
    task_run_limits: TaskRunBudgetLimits | None = None,
) -> CloudFallbackDecision:
    """Section 52: server-only cloud fallback when policy permits."""
    active = policy or RoutingPolicy.load()
    threshold = active.cloud_after_seconds
    digest = policy_hash(active)

    if not customer_allows_cloud:
        return CloudFallbackDecision(False, "customer_policy_blocked", edge_wait_seconds, threshold, digest)
    if not region_allows_cloud:
        return CloudFallbackDecision(False, "region_policy_blocked", edge_wait_seconds, threshold, digest)
    daily_cap = int(active.spec["fallback"]["dailyCloudCostCapMicros"])
    if cost_cap_remaining_micros is not None and cost_cap_remaining_micros <= 0:
        return CloudFallbackDecision(False, "daily_cost_cap_exhausted", edge_wait_seconds, threshold, digest)
    if edge_wait_seconds < threshold:
        return CloudFallbackDecision(
            False,
            "edge_wait_below_threshold",
            edge_wait_seconds,
            threshold,
            digest,
        )
    if daily_cap <= 0:
        return CloudFallbackDecision(False, "cloud_disabled", edge_wait_seconds, threshold, digest)

    trust = evaluate_cloud_fallback_trust(
        edge_wait_seconds=edge_wait_seconds,
        cloud_after_seconds=threshold,
        execution_policy=execution_policy,  # type: ignore[arg-type]
        cloud_fallback_allowed=customer_allows_cloud,
        data_region=data_region,
        cloud_region=cloud_region,
        data_owner_consent_granted=data_owner_consent_granted,
        cost_cap_remaining_micros=cost_cap_remaining_micros,
    )
    if not trust.permitted:
        return CloudFallbackDecision(False, trust.reason, edge_wait_seconds, threshold, digest)

    limits = task_run_limits or TaskRunBudgetLimits()
    usage = task_run_usage or TaskRunBudgetUsage(
        attempt_count=1,
        assignment_count=0,
        cloud_fallback_count=0,
    )
    if not cloud_fallback_budget_permitted(usage=usage, limits=limits):
        return CloudFallbackDecision(
            False,
            "task_run_cloud_budget_exhausted",
            edge_wait_seconds,
            threshold,
            digest,
        )

    return CloudFallbackDecision(True, "edge_wait_exceeded", edge_wait_seconds, threshold, digest)
