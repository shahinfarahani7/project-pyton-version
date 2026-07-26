from dataclasses import dataclass
from collections import defaultdict
from uuid import UUID
@dataclass(frozen=True, slots=True)
class Entry:
    account_id: UUID
    direction: str
    amount_micros: int
    currency: str

def validate(entries: list[Entry]) -> None:
    totals: dict[str, dict[str, int]] = defaultdict(lambda: {"debit": 0, "credit": 0})
    for entry in entries:
        totals[entry.currency][entry.direction] += entry.amount_micros
    if any(x["debit"] != x["credit"] for x in totals.values()):
        raise ValueError("LEDGER_INVARIANT_FAILED")
