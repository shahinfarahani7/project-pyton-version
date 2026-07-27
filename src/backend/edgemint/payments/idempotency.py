from __future__ import annotations

from dataclasses import dataclass, field

from edgemint.payments.errors import payment_error


@dataclass
class IdempotencyStore:
    processed_keys: set[str] = field(default_factory=set)
    processed_event_ids: set[str] = field(default_factory=set)
    results: dict[str, dict] = field(default_factory=dict)

    def begin(self, key: str) -> None:
        if key in self.processed_keys:
            raise payment_error("IDEMPOTENCY_CONFLICT", detail=key)

    def complete(self, key: str, result: dict) -> dict:
        self.processed_keys.add(key)
        self.results[key] = result
        return result

    def get(self, key: str) -> dict | None:
        return self.results.get(key)

    def register_event(self, event_id: str) -> bool:
        if event_id in self.processed_event_ids:
            return False
        self.processed_event_ids.add(event_id)
        return True
