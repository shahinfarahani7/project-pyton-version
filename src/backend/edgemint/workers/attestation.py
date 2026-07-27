from __future__ import annotations

import hashlib
import secrets
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

from edgemint.building_blocks.settings import Settings, get_settings
from edgemint.workers.errors import worker_error


@dataclass(frozen=True, slots=True)
class ChallengeBundle:
    challenge_id: UUID
    nonce: str
    challenge_hash: bytes
    expires_at: datetime


def new_challenge(*, settings: Settings | None = None) -> ChallengeBundle:
    active = settings or get_settings()
    challenge_id = UUID(int=secrets.randbits(128))
    nonce = secrets.token_urlsafe(32)
    digest = hashlib.sha256(nonce.encode("utf-8")).digest()
    expires_at = datetime.now(UTC) + timedelta(seconds=active.worker_challenge_ttl_seconds)
    return ChallengeBundle(
        challenge_id=challenge_id,
        nonce=nonce,
        challenge_hash=digest,
        expires_at=expires_at,
    )


def public_key_fingerprint(public_key_pem: str) -> str:
    normalized = public_key_pem.strip().encode("utf-8")
    return hashlib.sha256(normalized).hexdigest()


def verify_attestation(
    *,
    attestation: dict[str, Any],
    challenge_nonce: str,
    public_key_pem: str | None,
    platform: str,
    settings: Settings | None = None,
) -> None:
    active = settings or get_settings()
    if not attestation:
        raise worker_error("ATTESTATION_INVALID", detail="missing attestation payload")
    if attestation.get("emulator") is True and active.environment in {"staging", "production"}:
        raise worker_error("EMULATOR_POLICY_BREACH")
    if attestation.get("rooted") is True and active.environment in {"staging", "production"}:
        raise worker_error("ATTESTATION_INVALID", detail="rooted device")
    expected_nonce = attestation.get("nonce") or attestation.get("challengeNonce")
    if expected_nonce != challenge_nonce:
        raise worker_error("ATTESTATION_INVALID", detail="nonce mismatch")
    if public_key_pem:
        declared = attestation.get("publicKeyFingerprint")
        if declared and declared != public_key_fingerprint(public_key_pem):
            raise worker_error("DEVICE_KEY_MISMATCH")
    if platform not in {"android", "ios", "linux_edge"}:
        raise worker_error("INPUT_SCHEMA_INVALID", detail="unsupported platform")
    if attestation.get("consentPolicyVersion") != active.worker_consent_policy_version:
        raise worker_error("CONSENT_MISMATCH")
