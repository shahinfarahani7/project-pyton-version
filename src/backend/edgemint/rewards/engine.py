from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from edgemint.pricing.money import apply_bps
from edgemint.rewards.policy import RewardPolicy, load_reward_policy


@dataclass(frozen=True, slots=True)
class RewardInput:
    task_type: str
    quanta: int
    tier: str
    quality_milli: int
    urgency: str
    scarcity_bps: int
    reliability_bps: int

    @classmethod
    def from_vector(cls, raw: dict[str, Any]) -> RewardInput:
        return cls(
            task_type=str(raw["taskType"]),
            quanta=int(raw["quanta"]),
            tier=str(raw["tier"]),
            quality_milli=int(raw["qualityMilli"]),
            urgency=str(raw["urgency"]),
            scarcity_bps=int(raw["scarcityBps"]),
            reliability_bps=int(raw["reliabilityBps"]),
        )


def compute_reward(raw_input: dict[str, Any], *, policy: RewardPolicy | None = None) -> dict[str, Any]:
    active = policy or load_reward_policy()
    reward_input = RewardInput.from_vector(raw_input)
    rule = active.rule_for(reward_input.task_type)
    quality_bps = max(
        (
            band["multiplierBps"]
            for band in active.spec["qualityBands"]
            if reward_input.quality_milli >= band["minimumMilli"]
        ),
        default=0,
    )
    multipliers = [
        ("tier", active.spec["multipliersBps"]["tier"][reward_input.tier]),
        ("quality", quality_bps),
        ("urgency", active.spec["multipliersBps"]["urgency"][reward_input.urgency]),
        ("scarcity", reward_input.scarcity_bps),
        ("reliability", reward_input.reliability_bps),
    ]
    running = rule["baseRewardMicrosPerQuantum"] * reward_input.quanta
    steps: list[dict[str, Any]] = []
    for name, bps in multipliers:
        running = apply_bps(running, bps) if running else 0
        steps.append({"name": name, "bps": bps, "runningMicros": running})
    eligible = reward_input.quality_milli >= 800
    if not eligible:
        running = 0
    return {
        "rewardMicros": running,
        "unit": active.unit,
        "eligible": eligible,
        "holdHours": active.spec["holds"]["defaultHours"],
        "steps": steps,
    }
