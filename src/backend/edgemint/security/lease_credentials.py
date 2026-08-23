from __future__ import annotations

import base64
import hashlib
import os
from dataclasses import dataclass
from uuid import UUID

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from edgemint.building_blocks.settings import Settings, get_settings


@dataclass(frozen=True, slots=True)
class LeaseCredentialCipher:
    """Encrypt lease capabilities at rest without making Outbox a secret store."""

    key: bytes

    @classmethod
    def from_settings(cls, settings: Settings | None = None) -> LeaseCredentialCipher:
        active = settings or get_settings()
        configured = active.lease_credential_encryption_key
        if configured:
            try:
                key = base64.urlsafe_b64decode(configured.encode("ascii"))
            except Exception as exc:
                raise RuntimeError("LEASE_CREDENTIAL_ENCRYPTION_KEY_INVALID") from exc
            if len(key) != 32:
                raise RuntimeError("LEASE_CREDENTIAL_ENCRYPTION_KEY_INVALID")
            return cls(key=key)
        if active.environment not in {"development", "test"}:
            raise RuntimeError("LEASE_CREDENTIAL_ENCRYPTION_KEY_REQUIRED")
        seed = active.jwt_signing_secret or "edgemint-development-lease-credential-key"
        return cls(key=hashlib.sha256(seed.encode("utf-8")).digest())

    def encrypt(self, lease_token: str, *, worker_device_id: UUID) -> bytes:
        nonce = os.urandom(12)
        ciphertext = AESGCM(self.key).encrypt(
            nonce,
            lease_token.encode("utf-8"),
            worker_device_id.bytes,
        )
        return nonce + ciphertext

    def decrypt(self, encrypted: bytes, *, worker_device_id: UUID) -> str:
        if len(encrypted) < 29:
            raise RuntimeError("LEASE_CREDENTIAL_CIPHERTEXT_INVALID")
        try:
            plaintext = AESGCM(self.key).decrypt(
                encrypted[:12],
                encrypted[12:],
                worker_device_id.bytes,
            )
            return plaintext.decode("utf-8")
        except Exception as exc:
            raise RuntimeError("LEASE_CREDENTIAL_DECRYPTION_FAILED") from exc
