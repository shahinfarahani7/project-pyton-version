from dataclasses import dataclass
from datetime import datetime
@dataclass(frozen=True, slots=True)
class IdempotencyContract:
    scope: str
    key: str
    request_sha256: str
    expires_at: datetime
@dataclass(frozen=True, slots=True)
class IdempotencyDecision:
    execute: bool
    replay: bool
    status: int | None = None
    body: bytes | None = None
