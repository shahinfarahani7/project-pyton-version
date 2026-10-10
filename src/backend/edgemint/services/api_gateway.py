from __future__ import annotations

import os
import secrets
from datetime import datetime, timedelta
from uuid import UUID

from fastapi import Header, HTTPException, Request, Response, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field

from edgemint.building_blocks.app import create_service_app
from edgemint.building_blocks.database import transaction
from edgemint.building_blocks.ids import public_id
from edgemint.building_blocks.settings import get_settings
from edgemint.security.context import AuthorizationContext, PrincipalContext, PrincipalKind
from edgemint.security.problems import raise_auth_error, request_trace_id
from edgemint.security.tokens import BrowserSessionStore, DelegatedTokenService, write_audit_event

app = create_service_app("api-gateway")
settings = get_settings()
session_store = BrowserSessionStore()
token_service = DelegatedTokenService(settings)

if settings.environment in {"development", "test"}:
    from edgemint.dev.dev_worker_api import router as dev_worker_router
    from edgemint.dev.portal_api import router as dev_portal_router

    app.include_router(dev_portal_router, tags=["customer-portal-dev"])
    app.include_router(dev_worker_router, tags=["worker-dev"])


class SessionCreateRequest(BaseModel):
    principalId: UUID
    workspaceId: UUID
    permissions: list[str] = Field(min_length=1)


class SessionResponse(BaseModel):
    sessionPublicId: str
    workspaceId: UUID
    authorizationGeneration: int
    expiresAt: datetime
    role: str = "customer"


class DelegatedTokenResponse(BaseModel):
    accessToken: str
    tokenType: str = "Bearer"
    expiresInSeconds: int


class EmailOtpChallengeRequest(BaseModel):
    email: str = Field(min_length=3, max_length=254)


class EmailOtpChallengeResponse(BaseModel):
    challengeId: str
    expiresInSeconds: int
    emailDispatched: bool = False
    devCode: str | None = None


class EmailOtpVerifyRequest(BaseModel):
    challengeId: str = Field(min_length=4, max_length=80)
    email: str = Field(min_length=3, max_length=254)
    code: str = Field(min_length=6, max_length=6)


class EmailPasswordRequest(BaseModel):
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=1, max_length=128)


class EmailSignupRequest(BaseModel):
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=8, max_length=128)


def _require_local_bff() -> None:
    if settings.environment not in {"development", "test"}:
        raise HTTPException(503, "OIDC_BFF_NOT_CONFIGURED")


def _try_send_otp(recipient: str, code: str) -> bool:
    host = os.environ.get("EDGEMINT_OTP_SMTP_HOST", "")
    if not host and settings.environment == "development":
        host = "mailpit"
    if not host:
        return False
    port = int(os.environ.get("EDGEMINT_OTP_SMTP_PORT", "1025"))
    from edgemint.dev.email_otp import deliver_otp_email

    try:
        deliver_otp_email(recipient, code, host=host, port=port)
    except OSError:
        return False
    return True


async def _issue_browser_session(
    response: Response,
    *,
    principal_id: UUID,
    workspace_id: UUID,
    details: dict[str, object],
    role: str = "customer",
) -> SessionResponse:
    session_token = secrets.token_urlsafe(32)
    csrf_secret = secrets.token_urlsafe(32)
    session_public_id = public_id("ses")
    async with transaction(workspace_id=workspace_id) as connection:
        record = await session_store.create_session(
            connection,
            public_id=session_public_id,
            principal_id=principal_id,
            workspace_id=workspace_id,
            session_token=session_token,
            csrf_secret=csrf_secret,
        )
        await write_audit_event(
            connection,
            workspace_id=workspace_id,
            actor_id=str(principal_id),
            action="auth.session.created",
            resource_type="browser_session",
            resource_id=session_public_id,
            details={**details, "authorizationGeneration": record.authorization_generation},
        )
    response.set_cookie(
        key=BrowserSessionStore.cookie_name(environment=settings.environment),
        value=session_token,
        httponly=True,
        secure=BrowserSessionStore.cookie_secure(environment=settings.environment),
        samesite="strict",
        path="/",
        max_age=int(timedelta(hours=12).total_seconds()),
    )
    response.headers[BrowserSessionStore.CSRF_HEADER] = csrf_secret
    return SessionResponse(
        sessionPublicId=session_public_id,
        workspaceId=workspace_id,
        authorizationGeneration=record.authorization_generation,
        expiresAt=record.absolute_expires_at,
        role=role,
    )


@app.post("/auth/sessions", response_model=SessionResponse, tags=["auth"])
async def create_browser_session(payload: SessionCreateRequest, response: Response) -> SessionResponse:
    _require_local_bff()
    return await _issue_browser_session(
        response,
        principal_id=payload.principalId,
        workspace_id=payload.workspaceId,
        details={},
    )


@app.post(
    "/auth/email-otp/challenges",
    response_model=EmailOtpChallengeResponse,
    response_model_exclude_none=True,
    tags=["auth"],
)
async def request_email_otp_challenge(payload: EmailOtpChallengeRequest) -> EmailOtpChallengeResponse:
    _require_local_bff()
    from edgemint.dev.email_otp import EmailOtpError, hydrate_local_accounts, request_email_otp

    await hydrate_local_accounts()
    try:
        issued = request_email_otp(payload.email, send=_try_send_otp)
    except EmailOtpError as exc:
        raise_auth_error(exc.code, status=exc.status, detail=exc.detail)
    dev_code = issued.code if settings.environment in {"development", "test"} else None
    return EmailOtpChallengeResponse(
        challengeId=issued.challenge_id,
        expiresInSeconds=issued.expires_in_seconds,
        emailDispatched=issued.email_dispatched,
        devCode=dev_code,
    )


@app.post("/auth/email-otp/verify", response_model=SessionResponse, tags=["auth"])
async def verify_email_otp_challenge(payload: EmailOtpVerifyRequest, response: Response) -> SessionResponse:
    _require_local_bff()
    from edgemint.dev.email_otp import EmailOtpError, hydrate_local_accounts, verify_email_otp

    await hydrate_local_accounts()
    try:
        identity = verify_email_otp(payload.challengeId, payload.email, payload.code)
    except EmailOtpError as exc:
        raise_auth_error(exc.code, status=exc.status, detail=exc.detail)
    return await _issue_browser_session(
        response,
        principal_id=identity.principal_id,
        workspace_id=identity.workspace_id,
        details={"method": "email_otp"},
        role=identity.role,
    )


@app.post("/auth/email-password", response_model=SessionResponse, tags=["auth"])
async def login_with_email_password(payload: EmailPasswordRequest, response: Response) -> SessionResponse:
    _require_local_bff()
    from edgemint.dev.email_otp import EmailOtpError, hydrate_local_accounts, verify_email_password

    await hydrate_local_accounts()
    try:
        identity = verify_email_password(payload.email, payload.password)
    except EmailOtpError as exc:
        raise_auth_error(exc.code, status=exc.status, detail=exc.detail)
    return await _issue_browser_session(
        response,
        principal_id=identity.principal_id,
        workspace_id=identity.workspace_id,
        details={"method": "email_password"},
        role=identity.role,
    )


@app.post("/auth/email-signup", response_model=SessionResponse, status_code=201, tags=["auth"])
async def signup_with_email_password(payload: EmailSignupRequest, response: Response) -> SessionResponse:
    _require_local_bff()
    from edgemint.dev.email_otp import (
        EmailOtpError,
        forget_local_account,
        hydrate_local_accounts,
        normalize_email,
        persist_local_account,
        register_local_account,
    )

    await hydrate_local_accounts()
    try:
        identity = register_local_account(payload.email, payload.password)
    except EmailOtpError as exc:
        raise_auth_error(exc.code, status=exc.status, detail=exc.detail)
    normalized = normalize_email(payload.email)
    try:
        await persist_local_account(identity, normalized)
    except Exception:
        forget_local_account(normalized)
        raise HTTPException(503, "LOCAL_SIGNUP_UNAVAILABLE") from None
    return await _issue_browser_session(
        response,
        principal_id=identity.principal_id,
        workspace_id=identity.workspace_id,
        details={"method": "email_signup"},
        role=identity.role,
    )


@app.post("/auth/sessions/logout", tags=["auth"])
async def logout_session(
    request: Request,
    response: Response,
    csrf_token: str | None = Header(default=None, alias=BrowserSessionStore.CSRF_HEADER),
) -> dict[str, str]:
    session_token = BrowserSessionStore.read_session_cookie(
        request.cookies, environment=settings.environment
    )
    if not session_token:
        raise_auth_error("AUTH_INVALID_CREDENTIAL")
    async with transaction() as connection:
        record = await session_store.load_by_token(connection, session_token=session_token)
        if record is None or not record.is_active():
            raise_auth_error("AUTH_SESSION_REVOKED")
        await session_store.revoke(connection, session_id=record.session_id, reason="logout")
        await write_audit_event(
            connection,
            workspace_id=record.workspace_id,
            actor_id=str(record.principal_id),
            action="auth.session.revoked",
            resource_type="browser_session",
            resource_id=record.public_id,
            details={"reason": "logout"},
        )
    response.delete_cookie(
        BrowserSessionStore.cookie_name(environment=settings.environment),
        path="/",
    )
    return {"status": "revoked"}


@app.post("/auth/delegated-token", response_model=DelegatedTokenResponse, tags=["auth"])
async def issue_delegated_token(request: Request) -> DelegatedTokenResponse:
    session_token = BrowserSessionStore.read_session_cookie(
        request.cookies, environment=settings.environment
    )
    if not session_token:
        raise_auth_error("AUTH_INVALID_CREDENTIAL")
    async with transaction() as connection:
        record = await session_store.load_by_token(connection, session_token=session_token)
        if record is None or not record.is_active():
            raise_auth_error("AUTH_SESSION_REVOKED")
        auth = AuthorizationContext(
            principal=PrincipalContext(
                principal_id=record.principal_id,
                subject=str(record.principal_id),
                kind=PrincipalKind.USER,
                permissions=frozenset({"customer.tasks:read", "customer.tasks:write"}),
            ),
            workspace_id=record.workspace_id,
            authorization_generation=record.authorization_generation,
            session_id=record.session_id,
            request_id=request_trace_id(request),
        )
        token = token_service.issue(auth=auth)
    return DelegatedTokenResponse(accessToken=token, expiresInSeconds=120)


@app.get("/auth/health", tags=["auth"])
async def auth_health() -> dict[str, str]:
    bff = "enabled" if settings.environment in {"development", "test"} else "oidc-required"
    return {"status": "ready", "bff": bff}


@app.websocket("/events/v1")
async def browser_events_proxy(websocket: WebSocket) -> None:
    """Public browser WebSocket edge. Validates BFF session and rejects direct credential frames."""
    origin = websocket.headers.get("origin")
    if settings.environment not in {"development", "test"} and not origin:
        await websocket.close(code=1008, reason="ORIGIN_REQUIRED")
        return

    session_token = BrowserSessionStore.read_session_cookie(
        websocket.cookies, environment=settings.environment
    )
    if not session_token and settings.environment in {"development", "test"}:
        authorization = websocket.headers.get("authorization", "")
        if authorization.startswith("Bearer "):
            await websocket.accept(subprotocol="edgemint.events.v1")
            await websocket.send_json(
                {
                    "type": "error",
                    "requestId": public_id("req"),
                    "code": "DELEGATED_PROXY_NOT_CONFIGURED",
                    "message": "Configure relay upstream for development bearer proxying",
                    "retryable": False,
                }
            )
            await websocket.close(code=1013, reason="RELAY_UPSTREAM_NOT_CONFIGURED")
            return

    if not session_token:
        await websocket.close(code=1008, reason="SESSION_REQUIRED")
        return

    async with transaction() as connection:
        record = await session_store.load_by_token(connection, session_token=session_token)
        if record is None or not record.is_active():
            await websocket.close(code=1008, reason="SESSION_REVOKED")
            return
        auth = AuthorizationContext(
            principal=PrincipalContext(
                principal_id=record.principal_id,
                subject=str(record.principal_id),
                kind=PrincipalKind.USER,
                permissions=frozenset({"customer.events:read"}),
            ),
            workspace_id=record.workspace_id,
            authorization_generation=record.authorization_generation,
            session_id=record.session_id,
        )
        delegated = token_service.issue(auth=auth, audience="edgemint-event-relay")

    offered = websocket.headers.get("sec-websocket-protocol", "")
    if "edgemint.events.v1" not in {item.strip() for item in offered.split(",")}:
        await websocket.close(code=1002, reason="SUBPROTOCOL_REQUIRED")
        return

    await websocket.accept(subprotocol="edgemint.events.v1")
    try:
        while True:
            frame = await websocket.receive_json()
            if frame.get("type") == "hello" and "authorization" in frame:
                await websocket.send_json(
                    {
                        "type": "error",
                        "requestId": frame.get("requestId", public_id("req")),
                        "code": "CREDENTIALS_IN_FRAME_FORBIDDEN",
                        "message": "Credentials must not appear in WebSocket frames",
                        "retryable": False,
                    }
                )
                continue
            if frame.get("type") == "hello":
                frame["_delegatedTokenIssued"] = True
                frame["_tokenAudience"] = "edgemint-event-relay"
                await websocket.send_json(
                    {
                        "type": "welcome",
                        "requestId": frame.get("requestId", public_id("req")),
                        "connectionId": "bff-proxy",
                        "resumeToken": delegated[:16],
                        "heartbeatSeconds": settings.websocket_heartbeat_seconds,
                        "maxInFlight": settings.websocket_max_in_flight,
                    }
                )
                continue
            await websocket.send_json(
                {
                    "type": "error",
                    "requestId": frame.get("requestId", public_id("req")),
                    "code": "BFF_PROXY_FRAME_BUFFERED",
                    "message": "Full relay proxy requires upstream websocket wiring",
                    "retryable": True,
                }
            )
    except WebSocketDisconnect:
        return
