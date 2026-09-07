from __future__ import annotations

from uuid import UUID

from edgemint.routing.cloud_fallback import evaluate_cloud_fallback
from edgemint.routing.policy import RoutingPolicy
from edgemint.security.tenant_data_trust import (
    evaluate_cloud_fallback_trust,
    evaluate_processing_permission,
    evaluate_worker_device_trust,
    verify_tenant_resource_scope,
)


def test_cross_tenant_artifact_access_denied() -> None:
    decision = verify_tenant_resource_scope(
        resource_workspace_id=UUID(int=1),
        request_workspace_id=UUID(int=2),
    )
    assert decision.permitted is False
    assert decision.reason == "cross_tenant_artifact"


def test_edge_only_blocks_cloud_destination_even_above_timer() -> None:
    policy = RoutingPolicy.load()
    decision = evaluate_cloud_fallback(
        edge_wait_seconds=float(policy.cloud_after_seconds + 10),
        policy=policy,
        execution_policy="edge_only",
    )
    assert decision.permitted is False
    assert decision.reason == "cloud_not_permitted"


def test_cloud_threshold_does_not_create_permission_below_timer() -> None:
    policy = RoutingPolicy.load()
    decision = evaluate_cloud_fallback_trust(
        edge_wait_seconds=float(policy.cloud_after_seconds - 5),
        cloud_after_seconds=policy.cloud_after_seconds,
        execution_policy="cloud_permitted",
        cloud_fallback_allowed=True,
        data_region="eu-central",
        cloud_region="eu-central",
    )
    assert decision.permitted is False
    assert decision.reason == "edge_wait_below_threshold"


def test_cloud_permitted_after_threshold_and_data_checks() -> None:
    policy = RoutingPolicy.load()
    decision = evaluate_cloud_fallback(
        edge_wait_seconds=float(policy.cloud_after_seconds + 1),
        policy=policy,
        execution_policy="cloud_permitted",
        cloud_region="eu-central",
    )
    assert decision.permitted is True
    assert decision.reason == "edge_wait_exceeded"


def test_prohibited_cloud_region_denied() -> None:
    decision = evaluate_processing_permission(
        execution_policy="cloud_permitted",
        destination="cloud_provider",
        data_region="eu-central",
        cloud_region="us-east",
    )
    assert decision.permitted is False
    assert decision.reason == "cloud_region_prohibited"


def test_revoked_worker_device_denied() -> None:
    decision = evaluate_worker_device_trust(
        worker_status="active",
        device_status="revoked",
        attestation_status="verified",
    )
    assert decision.permitted is False
    assert decision.reason == "revoked_worker_device"


def test_data_owner_consent_required() -> None:
    decision = evaluate_processing_permission(
        execution_policy="edge_preferred",
        destination="edge_worker",
        data_region="eu-central",
        data_owner_consent_granted=False,
    )
    assert decision.permitted is False
    assert decision.reason == "data_owner_consent_required"
