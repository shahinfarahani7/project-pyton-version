from __future__ import annotations
from dataclasses import dataclass

@dataclass(frozen=True, slots=True)
class Money:
    amount_micros: int
    currency: str = "EUR"
    def __post_init__(self) -> None:
        if isinstance(self.amount_micros, bool) or not isinstance(self.amount_micros, int):
            raise TypeError("Money must use integer micro-units")
    def __add__(self, other: "Money") -> "Money":
        if self.currency != other.currency:
            raise ValueError("CURRENCY_MISMATCH")
        return Money(self.amount_micros + other.amount_micros, self.currency)
