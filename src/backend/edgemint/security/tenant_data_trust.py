from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

from edgemint.security.data_policy_registry import (
    ActiveDataPolicy,
    ExecutionPolicyId,
    ProcessingDestination,
    load_active_data_policy,
)


@dataclass(frozen=True, slots=True)
class DataTrustDecision:
    permitted: bool
    reason: str
    policy_ref: str


def verify_tenant_resource_scope(
    *,
    resource_workspace_id: UUID,
    request_workspace_id: UUID,
) -> DataTrustDecision:
    policy_ref = load_active_data_policy()
    ref = f"DataPolicy/{policy_ref.name}@{policy_ref.version}"
    if resource_workspace_id != request_workspace_id:
        return DataTrustDecision(
            permitted=False,
            reason="cross_tenant_artifact",
            policy_ref=ref,
        )
    return DataTrustDecision(permitted=True, reason="tenant_scope_ok", policy_ref=ref)


def evaluate_processing_permission(
    *,
    execution_policy: ExecutionPolicyId,
    destination: ProcessingDestination,
    data_region: str,
    cloud_region: str | None = None,
    data_owner_consent_granted: bool = True,
    policy: ActiveDataPolicy | None = None,
) -> DataTrustDecision:
    active = policy or load_active_data_policy()
    ref = f"DataPolicy/{active.name}@{active.version}"
    rules = active.spec.processing

    if destination in rules.prohibitedDestinations:
        return DataTrustDecision(False, "data_destination_prohibited", ref)
    if rules.requireDataOwnerProcessingConsent and not data_owner_consent_granted:
        return DataTrustDecision(False, "data_owner_consent_required", ref)
    if execution_policy not in rules.allowedExecutionPolicies:
        return DataTrustDecision(False, "execution_policy_blocked", ref)

    if destination == "cloud_provider":
        if execution_policy == "edge_only":
            return DataTrustDecision(False, "cloud_not_permitted", ref)
        if cloud_region is None:
            return DataTrustDecision(False, "cloud_region_required", ref)
        if rules.regionEnforcement and cloud_region not in rules.permittedCloudRegions:
            return DataTrustDecision(False, "cloud_region_prohibited", ref)

    if rules.regionEnforcement and data_region and destination == "edge_worker":
        edge_profile = active.spec.trustProfiles.get("edge_worker")
        if edge_profile and edge_profile.permittedRegions:
            if data_region not in edge_profile.permittedRegions:
                return DataTrustDecision(False, "data_region_prohibited", ref)

    return DataTrustDecision(True, "processing_permitted", ref)


def evaluate_worker_device_trust(
    *,
    worker_status: str,
    device_status: str,
    attestation_status: str,
    trust_milli: int = 10_000,
    policy: ActiveDataPolicy | None = None,
) -> DataTrustDecision:
    active = policy or load_active_data_policy()
    ref = f"DataPolicy/{active.name}@{active.version}"
    if worker_status in {"banned", "quarantined"}:
        return DataTrustDecision(False, "revoked_worker_device", ref)
    if device_status != "active":
        return DataTrustDecision(False, "revoked_worker_device", ref)

    profile = active.spec.trustProfiles.get("edge_worker")
    if profile is None:
        return DataTrustDecision(True, "worker_trust_ok", ref)

    if device_status not in profile.allowedDeviceStatuses:
        return DataTrustDecision(False, "revoked_worker_device", ref)
    if profile.requiresAttestation and attestation_status not in {"verified", "passed", "active"}:
        return DataTrustDecision(False, "attestation_required", ref)
    if profile.minimumTrustMilli is not None and trust_milli < profile.minimumTrustMilli:
        return DataTrustDecision(False, "trust_too_low", ref)

    return DataTrustDecision(True, "worker_trust_ok", ref)


def evaluate_cloud_fallback_trust(
    *,
    edge_wait_seconds: float,
    cloud_after_seconds: int,
    execution_policy: ExecutionPolicyId,
    cloud_fallback_allowed: bool,
    data_region: str,
    cloud_region: str,
    data_owner_consent_granted: bool = True,
    cost_cap_remaining_micros: int | None = None,
    policy: ActiveDataPolicy | None = None,
) -> DataTrustDecision:
    """Section 52: timer threshold never creates permission without data/trust checks."""
    active = policy or load_active_data_policy()
    ref = f"DataPolicy/{active.name}@{active.version}"

    if edge_wait_seconds < cloud_after_seconds:
        return DataTrustDecision(False, "edge_wait_below_threshold", ref)
    if not cloud_fallback_allowed:
        return DataTrustDecision(False, "customer_policy_blocked", ref)
    if cost_cap_remaining_micros is not None and cost_cap_remaining_micros <= 0:
        return DataTrustDecision(False, "daily_cost_cap_exhausted", ref)

    processing = evaluate_processing_permission(
        execution_policy=execution_policy,
        destination="cloud_provider",
        data_region=data_region,
        cloud_region=cloud_region,
        data_owner_consent_granted=data_owner_consent_granted,
        policy=active,
    )
    if not processing.permitted:
        return processing
    return DataTrustDecision(True, "cloud_fallback_permitted", ref)
