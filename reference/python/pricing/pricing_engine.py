from dataclasses import dataclass

def ceiling_div(value: int, quantum: int) -> int: return (value + quantum - 1) // quantum
def apply_bps(value: int, bps: int) -> int: return (value * bps + 9_999) // 10_000
@dataclass(frozen=True, slots=True)
class PriceRule:
    task_type: str; unit_price_micros: int; quantum: int; minimum_charge_micros: int
@dataclass(frozen=True, slots=True)
class PriceInput:
    task_type: str; quantity: int; plan: str; priority: str; verification: str; region: str; execution_policy: str; retention: str
    def modifier_value(self, name: str) -> str:
        values = {"plan":self.plan,"priority":self.priority,"verification":self.verification,"region":self.region,"executionPolicy":self.execution_policy,"retention":self.retention}
        if name not in values: raise ValueError(f"UNKNOWN_PRICE_MODIFIER:{name}")
        return values[name]
@dataclass(frozen=True, slots=True)
class PricePolicy:
    currency: str; ordered_modifiers: tuple[str,...]; multipliers_bps: dict[str,dict[str,int]]; rules: tuple[PriceRule,...]
@dataclass(frozen=True, slots=True)
class PriceResult:
    base_micros: int; before_minimum_micros: int; charge_micros: int; minimum_applied: bool; currency: str

def quote(input: PriceInput, policy: PricePolicy) -> PriceResult:
    rule = next(r for r in policy.rules if r.task_type == input.task_type)
    base = ceiling_div(input.quantity, rule.quantum) * rule.unit_price_micros
    running = base
    for modifier in policy.ordered_modifiers:
        value = input.modifier_value(modifier)
        try: bps = policy.multipliers_bps[modifier][value]
        except KeyError as exc: raise ValueError(f"UNKNOWN_PRICE_MULTIPLIER:{modifier}:{value}") from exc
        running = apply_bps(running, bps)
    charge = max(running, rule.minimum_charge_micros)
    return PriceResult(base, running, charge, charge != running, policy.currency)
