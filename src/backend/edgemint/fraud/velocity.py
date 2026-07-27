from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any


@dataclass(frozen=True, slots=True)
class VelocityRule:
    name: str
    window_seconds: int
    max_events: int


DEFAULT_RULES = (
    VelocityRule(name="task_submissions", window_seconds=60, max_events=30),
    VelocityRule(name="claim_attempts", window_seconds=3600, max_events=5),
)


def evaluate_velocity(
    *,
    events: list[dict[str, Any]],
    rules: tuple[VelocityRule, ...] = DEFAULT_RULES,
) -> dict[str, Any]:
    now = datetime.now(UTC)
    triggered: list[str] = []
    for rule in rules:
        cutoff = now - timedelta(seconds=rule.window_seconds)
        count = sum(
            1
            for event in events
            if event.get("name") == rule.name and datetime.fromisoformat(str(event["occurredAt"])) >= cutoff
        )
        if count > rule.max_events:
            triggered.append(rule.name)
    return {"anomalyDetected": bool(triggered), "triggeredRules": triggered}
