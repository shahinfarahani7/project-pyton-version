from __future__ import annotations

from typing import Any

from edgemint.routing.policy import RoutingPolicy


def evaluate_eligibility(candidate: dict[str, Any], *, policy: RoutingPolicy | None = None) -> list[str]:
    active = policy or RoutingPolicy.load()
    rules = active.eligibility
    reasons: list[str] = []
    features = candidate["featuresBps"]
    if candidate["heartbeatAgeSeconds"] > rules["heartbeatMaximumAgeSeconds"]:
        reasons.append("STALE_HEARTBEAT")
    if features["trust"] < rules["minimumTrustMilli"] * 10:
        reasons.append("TRUST_TOO_LOW")
    if candidate["batteryPercent"] < rules["minimumBatteryPercent"]:
        reasons.append("BATTERY_TOO_LOW")
    if candidate["thermalState"] in rules["disallowedThermalStates"]:
        reasons.append("THERMAL_BLOCK")
    if rules["requireAttestationForPaidTasks"] and not candidate["attested"]:
        reasons.append("ATTESTATION_REQUIRED")
    if rules["requireCurrentConsent"] and not candidate["consentCurrent"]:
        reasons.append("CONSENT_REQUIRED")
    if rules["requireAvailableStatus"] and not candidate["available"]:
        reasons.append("WORKER_UNAVAILABLE")
    if rules["requireModelDigestMatch"] and not candidate["modelDigestMatch"]:
        reasons.append("MODEL_DIGEST_MISMATCH")
    if rules["requireRuntimeAbiMatch"] and not candidate["runtimeAbiMatch"]:
        reasons.append("RUNTIME_ABI_MISMATCH")
    if rules["respectCustomerRegion"] and not candidate["regionAllowed"]:
        reasons.append("REGION_NOT_ALLOWED")
    if rules["respectWorkerNetworkPolicy"] and not candidate["networkPolicyAllowed"]:
        reasons.append("NETWORK_POLICY_BLOCKED")
    return reasons


def compute_weighted_score(features_bps: dict[str, int], *, policy: RoutingPolicy | None = None) -> int:
    active = policy or RoutingPolicy.load()
    return sum(features_bps[name] * weight // 10000 for name, weight in active.score_weights_bps.items())


def evaluate_candidate(candidate: dict[str, Any], *, policy: RoutingPolicy | None = None) -> dict[str, Any]:
    active = policy or RoutingPolicy.load()
    reasons = evaluate_eligibility(candidate, policy=active)
    score = compute_weighted_score(candidate["featuresBps"], policy=active)
    return {
        "eligible": not reasons,
        "ineligibilityReasons": reasons,
        "score": score,
        "tieBreaker": active.spec["score"]["tieBreaker"].split("(")[0],
    }
