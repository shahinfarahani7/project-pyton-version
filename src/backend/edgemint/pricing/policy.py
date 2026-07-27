from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

from edgemint.pricing.money import apply_bps, ceil_div


@dataclass(frozen=True, slots=True)
class PriceRule:
    task_type: str
    quantum: int
    unit_price_micros: int
    minimum_charge_micros: int


@dataclass(frozen=True, slots=True)
class MarginFloors:
    minimum_contribution_margin_bps: int
    negative_margin_action: str


@dataclass(frozen=True, slots=True)
class PricePolicy:
    name: str
    version: str
    currency: str
    ordered_modifiers: tuple[str, ...]
    multipliers_bps: dict[str, dict[str, int]]
    rules: tuple[PriceRule, ...]
    quote_ttl_seconds: int
    discount_order: tuple[str, ...]
    floors: MarginFloors

    def rule_for(self, task_type: str) -> PriceRule:
        for rule in self.rules:
            if rule.task_type == task_type:
                return rule
        raise KeyError(f"UNKNOWN_TASK_TYPE:{task_type}")

    @property
    def version_label(self) -> str:
        return f"{self.name}@{self.version}"


def _parse_rule(raw: dict[str, Any]) -> PriceRule:
    return PriceRule(
        task_type=str(raw["taskType"]),
        quantum=int(raw["quantum"]),
        unit_price_micros=int(raw["unitPriceMicros"]),
        minimum_charge_micros=int(raw["minimumChargeMicros"]),
    )


def load_price_policy(path: Path | None = None) -> PricePolicy:
    base = path or (
        Path(__file__).resolve().parents[4]
        / "dsl"
        / "policies"
        / "pricing"
        / "public-eur-2026q3-v2.yaml"
    )
    document = yaml.safe_load(base.read_text(encoding="utf-8"))
    metadata = document["metadata"]
    spec = document["spec"]
    floors_raw = spec["floors"]
    return PricePolicy(
        name=str(metadata["name"]),
        version=str(metadata["version"]),
        currency=str(spec["currency"]),
        ordered_modifiers=tuple(spec["orderedModifiers"]),
        multipliers_bps={
            modifier: {str(k): int(v) for k, v in values.items()}
            for modifier, values in spec["multipliersBps"].items()
        },
        rules=tuple(_parse_rule(rule) for rule in spec["rules"]),
        quote_ttl_seconds=int(spec["quoteTtlSeconds"]),
        discount_order=tuple(spec.get("discountOrder") or ()),
        floors=MarginFloors(
            minimum_contribution_margin_bps=int(floors_raw["minimumContributionMarginBps"]),
            negative_margin_action=str(floors_raw["negativeMarginAction"]),
        ),
    )


def compute_base_micros(*, quantity: int, rule: PriceRule) -> int:
    if quantity <= 0:
        raise ValueError("QUANTITY_MUST_BE_POSITIVE")
    units = ceil_div(quantity, rule.quantum)
    base = units * rule.unit_price_micros
    if base > 2**62:
        raise OverflowError("PRICE_OVERFLOW")
    return base


def apply_ordered_modifiers(
    *,
    running_micros: int,
    modifiers: tuple[str, ...],
    multipliers_bps: dict[str, dict[str, int]],
    values: dict[str, str],
) -> tuple[int, list[dict[str, Any]]]:
    steps: list[dict[str, Any]] = []
    running = running_micros
    for modifier in modifiers:
        value = values[modifier]
        try:
            bps = multipliers_bps[modifier][value]
        except KeyError as exc:
            raise KeyError(f"UNKNOWN_PRICE_MULTIPLIER:{modifier}:{value}") from exc
        running = apply_bps(running, bps)
        steps.append(
            {
                "modifier": modifier,
                "value": value,
                "bps": bps,
                "runningMicros": running,
            }
        )
    return running, steps
