from __future__ import annotations

import secrets
import time
from dataclasses import dataclass
from uuid import UUID

_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"


def uuid7() -> UUID:
    """Generate an RFC 9562 UUIDv7 for application-side transient identifiers."""
    unix_ms = int(time.time_ns() // 1_000_000) & ((1 << 48) - 1)
    random_a = secrets.randbits(12)
    random_b = secrets.randbits(62)
    value = (unix_ms << 80) | (0x7 << 76) | (random_a << 64) | (0b10 << 62) | random_b
    return UUID(int=value)


@dataclass(frozen=True, slots=True)
class EntityId:
    value: UUID

    @classmethod
    def new(cls) -> "EntityId":
        return cls(uuid7())


def public_id(prefix: str) -> str:
    return f"{prefix}_{''.join(secrets.choice(_ALPHABET) for _ in range(26))}"
