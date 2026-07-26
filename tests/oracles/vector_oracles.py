from __future__ import annotations

from collections import defaultdict
from pathlib import Path
from typing import Any
import yaml

ROOT = Path(__file__).resolve().parents[2]


def _load(rel: str) -> dict[str, Any]:
    return yaml.safe_load((ROOT / rel).read_text(encoding="utf-8"))["spec"]


PRICE = _load("dsl/policies/pricing/public-eur-2026q3-v2.yaml")
REWARD = _load("dsl/policies/rewards/worker-reward-v2.yaml")
ROUTING = _load("dsl/policies/routing/smart-router-v2.yaml")
CLAIM = _load("dsl/policies/claims/edge-claim-v2.yaml")
WEBHOOK = _load("dsl/policies/webhooks/webhook-v2.yaml")
FRAUD = _load("dsl/policies/fraud/fraud-score-v2.yaml")
TASK_SM = _load("dsl/workflows/task-lifecycle.yaml")


def ceil_div(a: int, b: int) -> int:
    return (a + b - 1) // b


def apply_bps(value: int, bps: int) -> int:
    return (value * bps + 9999) // 10000


def pricing(inp: dict[str, Any]) -> dict[str, Any]:
    rule = next(r for r in PRICE["rules"] if r["taskType"] == inp["taskType"])
    base = ceil_div(inp["quantity"], rule["quantum"]) * rule["unitPriceMicros"]
    running = base
    steps = []
    for modifier in PRICE["orderedModifiers"]:
        bps = PRICE["multipliersBps"][modifier][inp[modifier]]
        running = apply_bps(running, bps)
        steps.append({"modifier": modifier, "value": inp[modifier], "bps": bps, "runningMicros": running})
    before = running
    charge = max(before, rule["minimumChargeMicros"])
    return {
        "baseMicros": base,
        "beforeMinimumMicros": before,
        "chargeMicros": charge,
        "minimumApplied": charge != before,
        "currency": PRICE["currency"],
        "steps": steps,
    }


def reward(inp: dict[str, Any]) -> dict[str, Any]:
    rule = next(r for r in REWARD["rules"] if r["taskType"] == inp["taskType"])
    quality_bps = max(
        (band["multiplierBps"] for band in REWARD["qualityBands"] if inp["qualityMilli"] >= band["minimumMilli"]),
        default=0,
    )
    multipliers = [
        ("tier", REWARD["multipliersBps"]["tier"][inp["tier"]]),
        ("quality", quality_bps),
        ("urgency", REWARD["multipliersBps"]["urgency"][inp["urgency"]]),
        ("scarcity", inp["scarcityBps"]),
        ("reliability", inp["reliabilityBps"]),
    ]
    running = rule["baseRewardMicrosPerQuantum"] * inp["quanta"]
    steps = []
    for name, bps in multipliers:
        running = apply_bps(running, bps) if running else 0
        steps.append({"name": name, "bps": bps, "runningMicros": running})
    eligible = inp["qualityMilli"] >= 800
    if not eligible:
        running = 0
    return {
        "rewardMicros": running,
        "unit": REWARD["unit"],
        "eligible": eligible,
        "holdHours": REWARD["holds"]["defaultHours"],
        "steps": steps,
    }


def routing(inp: dict[str, Any]) -> dict[str, Any]:
    eligibility = ROUTING["eligibility"]
    reasons: list[str] = []
    features = inp["featuresBps"]
    if inp["heartbeatAgeSeconds"] > eligibility["heartbeatMaximumAgeSeconds"]:
        reasons.append("STALE_HEARTBEAT")
    if features["trust"] < eligibility["minimumTrustMilli"] * 10:
        reasons.append("TRUST_TOO_LOW")
    if inp["batteryPercent"] < eligibility["minimumBatteryPercent"]:
        reasons.append("BATTERY_TOO_LOW")
    if inp["thermalState"] in eligibility["disallowedThermalStates"]:
        reasons.append("THERMAL_BLOCK")
    if eligibility["requireAttestationForPaidTasks"] and not inp["attested"]:
        reasons.append("ATTESTATION_REQUIRED")
    if eligibility["requireCurrentConsent"] and not inp["consentCurrent"]:
        reasons.append("CONSENT_REQUIRED")
    if eligibility["requireAvailableStatus"] and not inp["available"]:
        reasons.append("WORKER_UNAVAILABLE")
    if eligibility["requireModelDigestMatch"] and not inp["modelDigestMatch"]:
        reasons.append("MODEL_DIGEST_MISMATCH")
    if eligibility["requireRuntimeAbiMatch"] and not inp["runtimeAbiMatch"]:
        reasons.append("RUNTIME_ABI_MISMATCH")
    if eligibility["respectCustomerRegion"] and not inp["regionAllowed"]:
        reasons.append("REGION_NOT_ALLOWED")
    if eligibility["respectWorkerNetworkPolicy"] and not inp["networkPolicyAllowed"]:
        reasons.append("NETWORK_POLICY_BLOCKED")
    score = sum(
        features[name] * weight // 10000
        for name, weight in ROUTING["score"]["weightsBps"].items()
    )
    return {
        "eligible": not reasons,
        "ineligibilityReasons": reasons,
        "score": score,
        "tieBreaker": "hmac_sha256",
    }


def ledger(inp: dict[str, Any]) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    charge = inp["chargeMicros"]
    worker_reward = inp["rewardMicros"]
    refund = inp["refundMicros"]
    entries = [
        {"account": "2000", "direction": "debit", "amount": charge, "currency": "EUR_MICROS"},
        {"account": "4000", "direction": "credit", "amount": charge, "currency": "EUR_MICROS"},
    ]
    if worker_reward:
        entries += [
            {"account": "5000", "direction": "debit", "amount": worker_reward, "currency": "EUR_REWARD_MICROS"},
            {"account": "2100", "direction": "credit", "amount": worker_reward, "currency": "EUR_REWARD_MICROS"},
        ]
    if refund:
        entries += [
            {"account": "4400", "direction": "debit", "amount": refund, "currency": "EUR_MICROS"},
            {"account": "2000", "direction": "credit", "amount": refund, "currency": "EUR_MICROS"},
        ]
    sums: dict[str, int] = defaultdict(int)
    for entry in entries:
        sums[entry["currency"]] += entry["amount"] if entry["direction"] == "debit" else -entry["amount"]
    expected = {"balancedByCurrency": all(v == 0 for v in sums.values()), "currencies": sorted(sums)}
    return entries, expected


def task_lifecycle(inp: dict[str, Any]) -> dict[str, Any]:
    if inp["expectedVersion"] != inp["actualVersion"]:
        return {"allowed": False, "reason": "VERSION_CONFLICT"}
    transitions = {(t["from"], t["to"]) for t in TASK_SM["transitions"]}
    allowed = (inp["from"], inp["to"]) in transitions
    return {"allowed": allowed, "reason": "OK" if allowed else "TASK_INVALID_TRANSITION"}


def webhook(inp: dict[str, Any]) -> dict[str, Any]:
    status = inp["httpStatus"]
    attempt = inp["attempt"]
    success = 200 <= status <= 299
    retry = not success and status in set(WEBHOOK["retryStatusCodes"]) and attempt < WEBHOOK["retry"]["maximumAttempts"]
    delays = WEBHOOK["retry"]["delaysSeconds"]
    delay = delays[min(attempt - 1, len(delays) - 1)] if retry else 0
    return {"success": success, "retry": retry, "baseDelaySeconds": delay, "terminal": not success and not retry}


def claim(inp: dict[str, Any]) -> dict[str, Any]:
    cfg = CLAIM["eligibility"]
    reasons: list[str] = []
    if not inp["policyEnabled"]:
        reasons.append("CLAIMS_DISABLED")
    if inp["verifiedRewardMicros"] < cfg["minimumVerifiedRewardMicros"]:
        reasons.append("MINIMUM_NOT_MET")
    if cfg["kycRequired"] and not inp["kycApproved"]:
        reasons.append("KYC_REQUIRED")
    if cfg["sanctionsScreeningRequired"] and not inp["sanctionsClear"]:
        reasons.append("SANCTIONS_SCREENING_REQUIRED")
    if cfg["jurisdictionAllowlistRequired"] and not inp["jurisdictionAllowed"]:
        reasons.append("JURISDICTION_NOT_ALLOWED")
    if cfg["fraudHoldMustBeClear"] and inp["fraudHold"]:
        reasons.append("FRAUD_HOLD")
    if cfg["destinationVerificationRequired"] and not inp["destinationVerified"]:
        reasons.append("DESTINATION_NOT_VERIFIED")
    return {"eligible": not reasons, "reasons": reasons}


def fraud(inp: dict[str, Any]) -> dict[str, Any]:
    score = min(
        sum(FRAUD["signals"][name]["weightBps"] for name, enabled in inp.items() if enabled),
        FRAUD["scoreScaleBps"],
    )
    band = next(b for b in sorted(FRAUD["actionBands"], key=lambda x: x["minimumScoreBps"], reverse=True) if score >= b["minimumScoreBps"])
    return {"riskScoreBps": score, "actions": band["actions"], "rewardHold": band["rewardHold"]}


def worker_resume(inp: dict[str, Any]) -> dict[str, Any]:
    resume = all(inp.values())
    return {"resume": resume, "action": "resume_from_checkpoint" if resume else "abandon_attempt_and_requeue"}


ORACLES = {
    "pricing-vectors.jsonl": lambda case: (None, pricing(case["input"])),
    "reward-vectors.jsonl": lambda case: (None, reward(case["input"])),
    "routing-vectors.jsonl": lambda case: (None, routing(case["input"])),
    "ledger-vectors.jsonl": lambda case: ledger(case["input"]),
    "task-lifecycle-vectors.jsonl": lambda case: (None, task_lifecycle(case["input"])),
    "webhook-vectors.jsonl": lambda case: (None, webhook(case["input"])),
    "claim-vectors.jsonl": lambda case: (None, claim(case["input"])),
    "fraud-vectors.jsonl": lambda case: (None, fraud(case["input"])),
    "worker-resume-vectors.jsonl": lambda case: (None, worker_resume(case["input"])),
}
