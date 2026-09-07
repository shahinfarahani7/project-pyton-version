from __future__ import annotations

from edgemint.routing.cloud_fallback import evaluate_cloud_fallback
from edgemint.routing.policy import RoutingPolicy


def test_cloud_fallback_blocked_when_customer_disallows() -> None:
    decision = evaluate_cloud_fallback(
        edge_wait_seconds=120,
        policy=RoutingPolicy.load(),
        customer_allows_cloud=False,
    )
    assert decision.permitted is False
    assert decision.reason == "customer_policy_blocked"


def test_cloud_fallback_permitted_after_threshold() -> None:
    policy = RoutingPolicy.load()
    decision = evaluate_cloud_fallback(
        edge_wait_seconds=float(policy.cloud_after_seconds + 1),
        policy=policy,
    )
    assert decision.permitted is True
    assert decision.reason == "edge_wait_exceeded"
    assert decision.cloudAfterSeconds == policy.cloud_after_seconds


def test_cloud_fallback_blocked_below_threshold() -> None:
    policy = RoutingPolicy.load()
    decision = evaluate_cloud_fallback(
        edge_wait_seconds=float(policy.cloud_after_seconds - 1),
        policy=policy,
    )
    assert decision.permitted is False
    assert decision.reason == "edge_wait_below_threshold"
