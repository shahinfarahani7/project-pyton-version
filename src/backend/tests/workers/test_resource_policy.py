from __future__ import annotations

import pytest

from edgemint.workers.resource_policy import (
    approved_percent_for_mode,
    build_contribution_policy_view,
    default_contribution_mode_id,
    load_active_user_resource_policy,
    validate_contribution_mode_id,
)


def test_active_policy_matches_architecture_section_64() -> None:
    policy = load_active_user_resource_policy()
    limits = policy.spec.resourcePolicy
    assert limits.defaultApprovedPercent == 30
    assert limits.maximumApprovedPercent == 50
    assert limits.safetyReservePercent == 15
    assert limits.heartbeatMaximumAgeSeconds == 30
    assert limits.overbookingAllowed is False
    assert policy.spec.assignmentLimits.absoluteMaximumPerDevice == 3


def test_contribution_modes_balanced_default_performance_opt_in() -> None:
    assert default_contribution_mode_id() == "balanced"
    balanced = validate_contribution_mode_id("balanced")
    performance = validate_contribution_mode_id("performance")
    assert balanced.approvedPercent == 30
    assert balanced.requiresExplicitOptIn is False
    assert performance.approvedPercent == 50
    assert performance.requiresExplicitOptIn is True
    assert approved_percent_for_mode("balanced") == 30
    assert approved_percent_for_mode("performance") == 50


def test_policy_view_is_server_authoritative() -> None:
    view = build_contribution_policy_view()
    assert view.policyRef == "UserResourcePolicy/production-resource-policy-v1@1.0.0"
    assert view.defaultModeId == "balanced"
    assert view.maximumApprovedPercent == 50
    assert len(view.contributionModes) == 2
    assert view.consentChangeBehavior.increaseAppliesToNewReservationsOnly is True
    assert view.contributionRequiresExplicitOptIn is True
    assert view.contributionEnabledByDefault is False
    assert view.cpuEnforcement is not None
    assert view.cpuEnforcement.measurementWindowMs == 5000


def test_unknown_mode_rejected() -> None:
    with pytest.raises(ValueError, match="unknown contribution mode"):
        validate_contribution_mode_id("turbo")
