from __future__ import annotations

import hashlib
import json
import secrets
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

import jwt
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.building_blocks.settings import Settings, get_settings
from edgemint.security.context import AuthorizationContext, PrincipalContext, PrincipalKind


@dataclass(frozen=True, slots=True)
class DelegatedTokenClaims:
    principal_id: UUID
    workspace_id: UUID
    permissions: frozenset[str]
    session_id: UUID | None
    authorization_generation: int
    audience: str
    token_id: str


class DelegatedTokenService:
    def __init__(self, settings: Settings | None = None) -> None:
        self._settings = settings or get_settings()

    def issue(
        self,
        *,
        auth: AuthorizationContext,
        audience: str = "edgemint-event-relay",
        ttl_seconds: int = 120,
    ) -> str:
        issuer = self._settings.jwt_issuer or "edgemint-local"
        now = datetime.now(UTC)
        payload = {
            "iss": issuer,
            "aud": audience,
            "sub": str(auth.principal.principal_id),
            "workspace_id": str(auth.workspace_id),
            "permissions": sorted(auth.principal.permissions),
            "authorization_generation": auth.authorization_generation,
            "jti": secrets.token_urlsafe(16),
            "iat": int(now.timestamp()),
            "exp": int((now + timedelta(seconds=ttl_seconds)).timestamp()),
        }
        if auth.session_id is not None:
            payload["session_id"] = str(auth.session_id)
        secret = self._require_signing_secret()
        return jwt.encode(payload, secret, algorithm="HS256")

    def verify(self, token: str, *, audience: str = "edgemint-event-relay") -> DelegatedTokenClaims:
        secret = self._require_signing_secret()
        issuer = self._settings.jwt_issuer or "edgemint-local"
        payload = jwt.decode(
            token,
            secret,
            algorithms=["HS256"],
            audience=audience,
            issuer=issuer,
            options={"require": ["exp", "iat", "sub", "workspace_id", "permissions", "jti"]},
        )
        return DelegatedTokenClaims(
            principal_id=UUID(payload["sub"]),
            workspace_id=UUID(payload["workspace_id"]),
            permissions=frozenset(payload["permissions"]),
            session_id=UUID(payload["session_id"]) if payload.get("session_id") else None,
            authorization_generation=int(payload.get("authorization_generation", 1)),
            audience=audience,
            token_id=str(payload["jti"]),
        )

    def to_authorization_context(self, claims: DelegatedTokenClaims) -> AuthorizationContext:
        principal = PrincipalContext(
            principal_id=claims.principal_id,
            subject=str(claims.principal_id),
            kind=PrincipalKind.USER,
            permissions=claims.permissions,
        )
        return AuthorizationContext(
            principal=principal,
            workspace_id=claims.workspace_id,
            authorization_generation=claims.authorization_generation,
            session_id=claims.session_id,
        )

    def _require_signing_secret(self) -> str:
        if self._settings.jwt_signing_secret:
            return self._settings.jwt_signing_secret
        if self._settings.environment in {"development", "test"}:
            return "edgemint-development-signing-secret"
        raise RuntimeError("JWT_SIGNING_SECRET_REQUIRED")


def hash_session_token(token: str) -> bytes:
    return hashlib.sha256(token.encode("utf-8")).digest()


@dataclass(frozen=True, slots=True)
class BrowserSessionRecord:
    session_id: UUID
    public_id: str
    principal_id: UUID
    workspace_id: UUID
    authorization_generation: int
    risk_state: str
    revoked: bool
    absolute_expires_at: datetime
    idle_expires_at: datetime

    def is_active(self, now: datetime | None = None) -> bool:
        current = now or datetime.now(UTC)
        return (
            not self.revoked
            and self.risk_state != "locked"
            and current <= self.absolute_expires_at
            and current <= self.idle_expires_at
        )


class BrowserSessionStore:
    SESSION_COOKIE = "__Host-edgemint-session"
    CSRF_HEADER = "X-CSRF-Token"

    async def create_session(
        self,
        connection: AsyncConnection,
        *,
        public_id: str,
        principal_id: UUID,
        workspace_id: UUID,
        session_token: str,
        csrf_secret: str,
        absolute_ttl: timedelta = timedelta(hours=12),
        idle_ttl: timedelta = timedelta(minutes=30),
    ) -> BrowserSessionRecord:
        now = datetime.now(UTC)
        row = (
            await connection.execute(
                text(
                    """
                    INSERT INTO public.browser_sessions(
                        public_id, principal_id, workspace_id, session_token_hash, csrf_secret_hash,
                        authorization_generation, absolute_expires_at_utc, idle_expires_at_utc
                    )
                    VALUES (
                        :public_id, :principal_id, :workspace_id, :session_token_hash, :csrf_secret_hash,
                        1, :absolute_expires_at, :idle_expires_at
                    )
                    RETURNING id, authorization_generation, risk_state, revoked_at_utc,
                              absolute_expires_at_utc, idle_expires_at_utc
                    """
                ),
                {
                    "public_id": public_id,
                    "principal_id": principal_id,
                    "workspace_id": workspace_id,
                    "session_token_hash": hash_session_token(session_token),
                    "csrf_secret_hash": hash_session_token(csrf_secret),
                    "absolute_expires_at": now + absolute_ttl,
                    "idle_expires_at": now + idle_ttl,
                },
            )
        ).one()
        return BrowserSessionRecord(
            session_id=row.id,
            public_id=public_id,
            principal_id=principal_id,
            workspace_id=workspace_id,
            authorization_generation=row.authorization_generation,
            risk_state=row.risk_state,
            revoked=row.revoked_at_utc is not None,
            absolute_expires_at=row.absolute_expires_at_utc,
            idle_expires_at=row.idle_expires_at_utc,
        )

    async def load_by_token(
        self, connection: AsyncConnection, *, session_token: str
    ) -> BrowserSessionRecord | None:
        row = (
            await connection.execute(
                text(
                    """
                    SELECT id, public_id, principal_id, workspace_id, authorization_generation,
                           risk_state, revoked_at_utc, absolute_expires_at_utc, idle_expires_at_utc
                    FROM public.browser_sessions
                    WHERE session_token_hash = :session_token_hash
                    """
                ),
                {"session_token_hash": hash_session_token(session_token)},
            )
        ).one_or_none()
        if row is None:
            return None
        return BrowserSessionRecord(
            session_id=row.id,
            public_id=row.public_id,
            principal_id=row.principal_id,
            workspace_id=row.workspace_id,
            authorization_generation=row.authorization_generation,
            risk_state=row.risk_state,
            revoked=row.revoked_at_utc is not None,
            absolute_expires_at=row.absolute_expires_at_utc,
            idle_expires_at=row.idle_expires_at_utc,
        )

    async def revoke(
        self,
        connection: AsyncConnection,
        *,
        session_id: UUID,
        reason: str,
    ) -> None:
        await connection.execute(
            text(
                """
                UPDATE public.browser_sessions
                SET revoked_at_utc = CURRENT_TIMESTAMP, revocation_reason = :reason
                WHERE id = :session_id AND revoked_at_utc IS NULL
                """
            ),
            {"session_id": session_id, "reason": reason},
        )

    def verify_csrf(self, provided: str, stored_hash: bytes) -> bool:
        return secrets.compare_digest(hash_session_token(provided), stored_hash)


async def write_audit_event(
    connection: AsyncConnection,
    *,
    workspace_id: UUID,
    actor_id: str,
    action: str,
    resource_type: str,
    resource_id: str,
    details: dict[str, Any],
) -> None:
    await connection.execute(
        text(
            """
            INSERT INTO public.audit_events(
                workspace_id, actor_id, action, resource_type, resource_id, details_json
            )
            VALUES (
                :workspace_id, :actor_id, :action, :resource_type, :resource_id, CAST(:details AS jsonb)
            )
            """
        ),
        {
            "workspace_id": workspace_id,
            "actor_id": actor_id,
            "action": action,
            "resource_type": resource_type,
            "resource_id": resource_id,
            "details": json.dumps(details, separators=(",", ":"), sort_keys=True),
        },
    )
