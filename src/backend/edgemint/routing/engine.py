from __future__ import annotations

from typing import Any

from edgemint.routing.hard_eligibility import evaluate_hard_eligibility
from edgemint.routing.policy import RoutingPolicy


def evaluate_eligibility(candidate: dict[str, Any], *, policy: RoutingPolicy | None = None) -> list[str]:
    return evaluate_hard_eligibility(candidate, policy=policy)


def compute_weighted_score(features_bps: dict[str, int], *, policy: RoutingPolicy | None = None) -> int:
    active = policy or RoutingPolicy.load()
    return sum(features_bps[name] * weight // 10000 for name, weight in active.score_weights_bps.items())


def evaluate_candidate(
    candidate: dict[str, Any],
    *,
    policy: RoutingPolicy | None = None,
    bypass_hard_eligibility: bool = False,
) -> dict[str, Any]:
    from edgemint.routing.scoring_features import enrich_candidate_features_bps

    active = policy or RoutingPolicy.load()
    reasons = evaluate_hard_eligibility(candidate, policy=active, bypass=bypass_hard_eligibility)
    features_bps = enrich_candidate_features_bps(candidate, policy=active)
    score = 0 if reasons else compute_weighted_score(features_bps, policy=active)
    return {
        "eligible": not reasons,
        "ineligibilityReasons": reasons,
        "score": score,
        "featuresBps": features_bps,
        "tieBreaker": active.spec["score"]["tieBreaker"].split("(")[0],
    }
