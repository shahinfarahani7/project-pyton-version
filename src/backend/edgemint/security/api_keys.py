from __future__ import annotations

import hashlib
import secrets
from dataclasses import dataclass


def hash_secret(value: str) -> bytes:
    return hashlib.sha256(value.encode("utf-8")).digest()


def generate_api_key() -> tuple[str, bytes]:
    raw = secrets.token_urlsafe(32)
    return raw, hash_secret(raw)


def verify_api_key(raw: str, stored_hash: bytes) -> bool:
    return secrets.compare_digest(hash_secret(raw), stored_hash)


@dataclass(frozen=True, slots=True)
class ApiCredentialRecord:
    public_id: str
    secret_hash: bytes
    permissions: frozenset[str]
    revoked: bool

    def verify(self, raw_secret: str) -> bool:
        if self.revoked:
            return False
        return verify_api_key(raw_secret, self.secret_hash)
