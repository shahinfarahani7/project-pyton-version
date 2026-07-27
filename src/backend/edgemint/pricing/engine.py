from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from edgemint.pricing.money import apply_bps
from edgemint.pricing.policy import (
    PricePolicy,
    apply_ordered_modifiers,
    compute_base_micros,
    load_price_policy,
)


@dataclass(frozen=True, slots=True)
class PriceInput:
    task_type: str
    quantity: int
    plan: str
    priority: str
    verification: str
    region: str
    execution_policy: str
    retention: str
    contract_discount_bps: int = 0
    promotion_discount_bps: int = 0
    expected_cost_micros: int | None = None
    stressed_cost_micros: int | None = None
    subsidy_reserved: bool = False

    def modifier_values(self) -> dict[str, str]:
        return {
            "plan": self.plan,
            "priority": self.priority,
            "verification": self.verification,
            "region": self.region,
            "executionPolicy": self.execution_policy,
            "retention": self.retention,
        }

    @classmethod
    def from_vector(cls, raw: dict[str, Any]) -> PriceInput:
        return cls(
            task_type=str(raw["taskType"]),
            quantity=int(raw["quantity"]),
            plan=str(raw["plan"]),
            priority=str(raw["priority"]),
            verification=str(raw["verification"]),
            region=str(raw["region"]),
            execution_policy=str(raw["executionPolicy"]),
            retention=str(raw["retention"]),
            contract_discount_bps=int(raw.get("contractDiscountBps", 0)),
            promotion_discount_bps=int(raw.get("promotionDiscountBps", 0)),
            expected_cost_micros=(
                int(raw["expectedCostMicros"]) if raw.get("expectedCostMicros") is not None else None
            ),
            stressed_cost_micros=(
                int(raw["stressedCostMicros"]) if raw.get("stressedCostMicros") is not None else None
            ),
            subsidy_reserved=bool(raw.get("subsidyReserved", False)),
        )


@dataclass(frozen=True, slots=True)
class PriceResult:
    base_micros: int
    before_minimum_micros: int
    charge_micros: int
    minimum_applied: bool
    currency: str
    steps: tuple[dict[str, Any], ...]
    policy_version: str

    def as_dict(self) -> dict[str, Any]:
        return {
            "baseMicros": self.base_micros,
            "beforeMinimumMicros": self.before_minimum_micros,
            "chargeMicros": self.charge_micros,
            "minimumApplied": self.minimum_applied,
            "currency": self.currency,
            "steps": list(self.steps),
        }


class PricingEngine:
    def __init__(self, policy: PricePolicy | None = None) -> None:
        self._policy = policy or load_price_policy()

    @property
    def policy(self) -> PricePolicy:
        return self._policy

    def quote(self, price_input: PriceInput) -> PriceResult:
        policy = self._policy
        if price_input.quantity <= 0:
            raise ValueError("QUANTITY_MUST_BE_POSITIVE")
        rule = policy.rule_for(price_input.task_type)
        base = compute_base_micros(quantity=price_input.quantity, rule=rule)
        running, steps = apply_ordered_modifiers(
            running_micros=base,
            modifiers=policy.ordered_modifiers,
            multipliers_bps=policy.multipliers_bps,
            values=price_input.modifier_values(),
        )
        for discount_name in policy.discount_order:
            bps = 0
            if discount_name == "contract":
                bps = price_input.contract_discount_bps
            elif discount_name == "promotion":
                bps = price_input.promotion_discount_bps
            if bps:
                running = apply_bps(running, 10_000 - bps)
                steps.append(
                    {
                        "modifier": discount_name,
                        "value": str(bps),
                        "bps": 10_000 - bps,
                        "runningMicros": running,
                    }
                )
        before_minimum = running
        charge = max(before_minimum, rule.minimum_charge_micros)
        result = PriceResult(
            base_micros=base,
            before_minimum_micros=before_minimum,
            charge_micros=charge,
            minimum_applied=charge != before_minimum,
            currency=policy.currency,
            steps=tuple(steps),
            policy_version=policy.version_label,
        )
        evaluate_margin_floor(
            charge_micros=charge,
            price_input=price_input,
            policy=policy,
        )
        return result


def evaluate_margin_floor(
    *,
    charge_micros: int,
    price_input: PriceInput,
    policy: PricePolicy,
) -> None:
    cost = price_input.stressed_cost_micros
    if cost is None:
        cost = price_input.expected_cost_micros
    if cost is None:
        return
    if charge_micros <= 0:
        raise PricingRejectedError("NEGATIVE_MARGIN_FLOOR", detail="non-positive charge")
    margin_bps = ((charge_micros - cost) * 10_000) // charge_micros
    if margin_bps >= policy.floors.minimum_contribution_margin_bps:
        return
    if (
        policy.floors.negative_margin_action == "reject_unless_subsidy_reserved"
        and price_input.subsidy_reserved
    ):
        return
    raise PricingRejectedError("NEGATIVE_MARGIN_FLOOR", detail=f"margin_bps={margin_bps}")


class PricingRejectedError(Exception):
    def __init__(self, code: str, *, detail: str | None = None) -> None:
        self.code = code
        self.detail = detail
        super().__init__(code)


def compute_price(raw_input: dict[str, Any], *, policy: PricePolicy | None = None) -> dict[str, Any]:
    engine = PricingEngine(policy)
    return engine.quote(PriceInput.from_vector(raw_input)).as_dict()
