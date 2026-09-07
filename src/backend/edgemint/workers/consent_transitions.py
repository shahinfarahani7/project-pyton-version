from __future__ import annotations

from dataclasses import dataclass

from edgemint.workers.resource_policy import ConsentChangeBehavior, load_active_user_resource_policy


def _stop_reaction_bound_ms() -> int | None:
    policy = load_active_user_resource_policy()
    if policy.spec.cpuEnforcement is None:
        return None
    return policy.spec.cpuEnforcement.controlStopReactionBoundMs


@dataclass(frozen=True, slots=True)
class ConsentTransitionPlan:
    previous_mode_id: str
    next_mode_id: str
    previous_percent: int
    next_percent: int
    apply_to_new_reservations_only: bool
    stop_new_stages_above_limit: bool
    revoke_new_work_immediately: bool
    stop_reaction_bound_ms: int | None = None


def plan_contribution_mode_transition(
    *,
    previous_mode_id: str,
    next_mode_id: str,
) -> ConsentTransitionPlan:
    policy = load_active_user_resource_policy()
    behavior = policy.spec.consentChangeBehavior
    previous_percent = _percent_for_mode(previous_mode_id, policy.spec.contributionModes)
    next_percent = _percent_for_mode(next_mode_id, policy.spec.contributionModes)
    increasing = next_percent > previous_percent
    decreasing = next_percent < previous_percent
    return ConsentTransitionPlan(
        previous_mode_id=previous_mode_id,
        next_mode_id=next_mode_id,
        previous_percent=previous_percent,
        next_percent=next_percent,
        apply_to_new_reservations_only=increasing and behavior.increaseAppliesToNewReservationsOnly,
        stop_new_stages_above_limit=decreasing and behavior.decreaseStopsNewStagesAboveLimit,
        revoke_new_work_immediately=False,
        stop_reaction_bound_ms=_stop_reaction_bound_ms() if decreasing else None,
    )


def plan_consent_revocation(*, current_mode_id: str) -> ConsentTransitionPlan:
    policy = load_active_user_resource_policy()
    behavior = policy.spec.consentChangeBehavior
    return ConsentTransitionPlan(
        previous_mode_id=current_mode_id,
        next_mode_id=current_mode_id,
        previous_percent=_percent_for_mode(current_mode_id, policy.spec.contributionModes),
        next_percent=0,
        apply_to_new_reservations_only=False,
        stop_new_stages_above_limit=True,
        revoke_new_work_immediately=behavior.revocationStopsNewWorkImmediately,
        stop_reaction_bound_ms=_stop_reaction_bound_ms(),
    )


def _percent_for_mode(mode_id: str, modes: list) -> int:
    for mode in modes:
        if mode.id == mode_id:
            return int(mode.approvedPercent)
    raise ValueError(f"unknown contribution mode: {mode_id}")
