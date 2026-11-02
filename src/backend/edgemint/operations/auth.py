from __future__ import annotations

import secrets
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

import jwt
from fastapi import Request

from edgemint.building_blocks.settings import Settings, get_settings
from edgemint.operations.errors import operations_error
from edgemint.operations.policy import ROLE_PERMISSIONS

OPERATOR_SESSION_AUDIENCE = "edgemint-operations"
OPERATOR_SESSION_TTL = timedelta(hours=8)
CSRF_HEADER = "X-CSRF-Token"
_SAFE_METHODS = frozenset({"GET", "HEAD", "OPTIONS"})


@dataclass(frozen=True, slots=True)
class OperatorSession:
    operator_id: str
    role: str
    mfa_verified: bool
    csrf_token: str
    expires_at: datetime

    @property
    def permissions(self) -> frozenset[str]:
        return ROLE_PERMISSIONS.get(self.role, frozenset())

    def require(self, permission: str) -> None:
        if permission not in self.permissions:
            raise operations_error("AUTH_SCOPE_REQUIRED", detail=permission)


def cookie_name(settings: Settings) -> str:
    if settings.environment in {"development", "test"}:
        return "edgemint-operator-session"
    return "__Host-edgemint-operator-session"


def dev_login_enabled(settings: Settings) -> bool:
    return settings.environment in {"development", "test"}


def _signing_secret(settings: Settings) -> str:
    if settings.jwt_signing_secret:
        return settings.jwt_signing_secret
    if settings.environment in {"development", "test"}:
        return "edgemint-development-signing-secret"
    raise RuntimeError("JWT_SIGNING_SECRET_REQUIRED")


def issue_operator_session(
    *,
    operator_id: str,
    role: str,
    mfa_verified: bool,
    settings: Settings | None = None,
    now: datetime | None = None,
) -> tuple[str, OperatorSession]:
    cfg = settings or get_settings()
    if role not in ROLE_PERMISSIONS:
        raise operations_error("INPUT_SCHEMA_INVALID", detail="unknown role")
    issued_at = now or datetime.now(UTC)
    session = OperatorSession(
        operator_id=operator_id,
        role=role,
        mfa_verified=mfa_verified,
        csrf_token=secrets.token_urlsafe(32),
        expires_at=issued_at + OPERATOR_SESSION_TTL,
    )
    token = jwt.encode(
        {
            "iss": cfg.jwt_issuer or "edgemint-local",
            "aud": OPERATOR_SESSION_AUDIENCE,
            "sub": operator_id,
            "role": role,
            "mfa": mfa_verified,
            "csrf": session.csrf_token,
            "jti": secrets.token_urlsafe(16),
            "iat": int(issued_at.timestamp()),
            "exp": int(session.expires_at.timestamp()),
        },
        _signing_secret(cfg),
        algorithm="HS256",
    )
    return token, session


def verify_operator_session(token: str, *, settings: Settings | None = None) -> OperatorSession:
    cfg = settings or get_settings()
    try:
        payload = jwt.decode(
            token,
            _signing_secret(cfg),
            algorithms=["HS256"],
            audience=OPERATOR_SESSION_AUDIENCE,
            issuer=cfg.jwt_issuer or "edgemint-local",
            options={"require": ["exp", "iat", "sub", "role", "mfa", "csrf"]},
        )
    except jwt.PyJWTError as exc:
        raise operations_error("AUTH_REQUIRED") from exc
    if payload["role"] not in ROLE_PERMISSIONS:
        raise operations_error("AUTH_REQUIRED")
    return OperatorSession(
        operator_id=str(payload["sub"]),
        role=str(payload["role"]),
        mfa_verified=bool(payload["mfa"]),
        csrf_token=str(payload["csrf"]),
        expires_at=datetime.fromtimestamp(int(payload["exp"]), UTC),
    )


async def require_operator(request: Request) -> OperatorSession:
    settings = get_settings()
    token = request.cookies.get(cookie_name(settings))
    if not token:
        raise operations_error("AUTH_REQUIRED")
    session = verify_operator_session(token, settings=settings)
    if not session.mfa_verified:
        raise operations_error("MFA_REQUIRED")
    if request.method not in _SAFE_METHODS:
        provided = request.headers.get(CSRF_HEADER, "")
        if not secrets.compare_digest(provided, session.csrf_token):
            raise operations_error("CSRF_INVALID")
    return session
