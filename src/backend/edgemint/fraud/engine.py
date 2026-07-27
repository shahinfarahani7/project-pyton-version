from __future__ import annotations

from typing import Any

from edgemint.fraud.policy import load_fraud_policy


def evaluate_fraud(raw_input: dict[str, Any]) -> dict[str, Any]:
    policy = load_fraud_policy().spec
    score = min(
        sum(policy["signals"][name]["weightBps"] for name, enabled in raw_input.items() if enabled),
        int(policy["scoreScaleBps"]),
    )
    band = next(
        band
        for band in sorted(policy["actionBands"], key=lambda item: item["minimumScoreBps"], reverse=True)
        if score >= band["minimumScoreBps"]
    )
    return {"riskScoreBps": score, "actions": band["actions"], "rewardHold": band["rewardHold"]}
