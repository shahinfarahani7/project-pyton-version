from __future__ import annotations

from pathlib import Path
from typing import Any
import yaml

ROOT = Path(__file__).resolve().parents[2]


def _load(rel: str) -> dict[str, Any]:
    return yaml.safe_load((ROOT / rel).read_text(encoding="utf-8"))["spec"]


PRICE = _load("dsl/policies/pricing/public-eur-2026q3-v2.yaml")
CLAIM = _load("dsl/policies/claims/edge-claim-v2.yaml")
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
    from edgemint.rewards.engine import compute_reward

    return compute_reward(inp)


def routing(inp: dict[str, Any]) -> dict[str, Any]:
    from edgemint.routing.engine import evaluate_candidate

    return evaluate_candidate(inp)


def ledger(inp: dict[str, Any]) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    from edgemint.ledger.engine import compute_ledger

    return compute_ledger(inp)


def task_lifecycle(inp: dict[str, Any]) -> dict[str, Any]:
    if inp["expectedVersion"] != inp["actualVersion"]:
        return {"allowed": False, "reason": "VERSION_CONFLICT"}
    transitions = {(t["from"], t["to"]) for t in TASK_SM["transitions"]}
    allowed = (inp["from"], inp["to"]) in transitions
    return {"allowed": allowed, "reason": "OK" if allowed else "TASK_INVALID_TRANSITION"}


def webhook(inp: dict[str, Any]) -> dict[str, Any]:
    from edgemint.webhooks.engine import evaluate_delivery

    return evaluate_delivery(inp)


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
    try:
        from edgemint.fraud.engine import evaluate_fraud

        return evaluate_fraud(inp)
    except ImportError:  # pragma: no cover
        score = min(
            sum(FRAUD["signals"][name]["weightBps"] for name, enabled in inp.items() if enabled),
            FRAUD["scoreScaleBps"],
        )
        band = next(
            b
            for b in sorted(FRAUD["actionBands"], key=lambda x: x["minimumScoreBps"], reverse=True)
            if score >= b["minimumScoreBps"]
        )
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
