from dataclasses import dataclass
@dataclass(frozen=True, slots=True)
class Money:
    amount_micros: int
    currency: str = "EUR"
    def add(self, other: "Money") -> "Money":
        if self.currency != other.currency: raise ValueError("CURRENCY_MISMATCH")
        return Money(self.amount_micros + other.amount_micros, self.currency)
