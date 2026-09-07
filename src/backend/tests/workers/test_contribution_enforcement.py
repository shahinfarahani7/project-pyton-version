from __future__ import annotations

from edgemint.workers.consent_transitions import plan_consent_revocation, plan_contribution_mode_transition
from edgemint.workers.contribution_enforcement import (
    approved_cpu_ceiling_bps,
    burst_ceiling_bps,
    cpu_usage_bps_from_units,
    evaluate_windowed_cpu_sample,
    load_cpu_enforcement_profile,
)
from edgemint.workers.resource_policy import load_active_user_resource_policy


def test_cpu_units_map_to_usage_bps() -> None:
    assert cpu_usage_bps_from_units(30) == 3000
    assert cpu_usage_bps_from_units(50) == 5000
    assert cpu_usage_bps_from_units(150) == 10_000


def test_approved_ceiling_scales_with_contribution_mode() -> None:
    balanced = approved_cpu_ceiling_bps(approved_percent=30, device_cpu_units=100)
    performance = approved_cpu_ceiling_bps(approved_percent=50, device_cpu_units=100)
    assert balanced == 3000
    assert performance == 5000
    assert performance > balanced


def test_windowed_cpu_sample_allows_burst_within_policy() -> None:
    profile = load_cpu_enforcement_profile()
    ceiling = approved_cpu_ceiling_bps(approved_percent=30, device_cpu_units=100)
    burst_limit = burst_ceiling_bps(approved_ceiling_bps=ceiling, tolerated_burst_bps=profile.toleratedBurstBps)
    ok, reason = evaluate_windowed_cpu_sample(
        observed_cpu_usage_bps=burst_limit,
        approved_ceiling_bps=ceiling,
        profile=profile,
    )
    assert ok is True
    assert reason is None
    over, over_reason = evaluate_windowed_cpu_sample(
        observed_cpu_usage_bps=burst_limit + 1,
        approved_ceiling_bps=ceiling,
        profile=profile,
    )
    assert over is False
    assert over_reason == "CPU_BUDGET_EXCEEDED"


def test_policy_exposes_cpu_enforcement_and_explicit_opt_in() -> None:
    policy = load_active_user_resource_policy()
    assert policy.spec.contributionRequiresExplicitOptIn is True
    assert policy.spec.contributionEnabledByDefault is False
    profile = policy.spec.cpuEnforcement
    assert profile is not None
    assert profile.measurementWindowMs == 5000
    assert profile.controlStopReactionBoundMs == 3000
    assert profile.enforcementMechanism == "windowed_cpu_share_v1"


def test_consent_decrease_and_revocation_include_stop_bound() -> None:
    decrease = plan_contribution_mode_transition(previous_mode_id="performance", next_mode_id="balanced")
    revoke = plan_consent_revocation(current_mode_id="balanced")
    assert decrease.stop_reaction_bound_ms == 3000
    assert revoke.stop_reaction_bound_ms == 3000
    assert revoke.revoke_new_work_immediately is True


def test_consent_increase_does_not_require_stop_bound() -> None:
    increase = plan_contribution_mode_transition(previous_mode_id="balanced", next_mode_id="performance")
    assert increase.apply_to_new_reservations_only is True
    assert increase.stop_reaction_bound_ms is None
