"""Signed admin handoff tokens so a customer-portal login can open the operations console.

Browser session cookies are host-only (`__Host-` / per-origin). api-gateway and operations
are separate processes, so an in-memory code cannot be redeemed across them. A short-lived
JWT signed with the shared JWT secret is verifiable by either service.
"""

from __future__ import annotations

import secrets
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

import jwt

from edgemint.building_blocks.settings import Settings, get_settings
from edgemint.operations.policy import ROLE_PERMISSIONS

HANDOFF_TTL = timedelta(minutes=2)
HANDOFF_AUDIENCE = "edgemint-operations-handoff"


@dataclass(frozen=True, slots=True)
class AdminHandoff:
    email: str
    role: str
    expires_at: datetime


def reset_admin_handoffs() -> None:
    """Kept for tests; signed tokens are stateless."""
    return None


def _signing_secret(settings: Settings) -> str:
    if settings.jwt_signing_secret:
        return settings.jwt_signing_secret
    if settings.environment in {"development", "test"}:
        return "edgemint-development-signing-secret"
    raise RuntimeError("JWT_SIGNING_SECRET_REQUIRED")


def issue_admin_handoff(
    *,
    email: str,
    role: str,
    settings: Settings | None = None,
    now: datetime | None = None,
) -> tuple[str, int]:
    if role not in ROLE_PERMISSIONS:
        raise ValueError("UNKNOWN_ROLE")
    cfg = settings or get_settings()
    issued_at = now or datetime.now(UTC)
    expires_at = issued_at + HANDOFF_TTL
    token = jwt.encode(
        {
            "iss": cfg.jwt_issuer or "edgemint-local",
            "aud": HANDOFF_AUDIENCE,
            "sub": email,
            "role": role,
            "jti": secrets.token_urlsafe(16),
            "iat": int(issued_at.timestamp()),
            "exp": int(expires_at.timestamp()),
        },
        _signing_secret(cfg),
        algorithm="HS256",
    )
    return token, int(HANDOFF_TTL.total_seconds())


def redeem_admin_handoff(
    code: str,
    *,
    settings: Settings | None = None,
    now: datetime | None = None,
) -> AdminHandoff:
    cfg = settings or get_settings()
    try:
        payload = jwt.decode(
            code,
            _signing_secret(cfg),
            algorithms=["HS256"],
            audience=HANDOFF_AUDIENCE,
            issuer=cfg.jwt_issuer or "edgemint-local",
            options={"require": ["exp", "sub", "role"]},
        )
    except jwt.PyJWTError as exc:
        raise ValueError("HANDOFF_INVALID") from exc
    email = str(payload.get("sub") or "").strip().lower()
    role = str(payload.get("role") or "").strip()
    if not email or role not in ROLE_PERMISSIONS:
        raise ValueError("HANDOFF_INVALID")
    expires_at = datetime.fromtimestamp(int(payload["exp"]), tz=UTC)
    if now is not None and now > expires_at:
        raise ValueError("HANDOFF_INVALID")
    return AdminHandoff(email=email, role=role, expires_at=expires_at)
