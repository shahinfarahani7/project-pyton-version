from __future__ import annotations

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
    from edgemint.dev.portal_api import router as dev_portal_router
    from edgemint.dev.dev_worker_api import router as dev_worker_router

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


class DelegatedTokenResponse(BaseModel):
    accessToken: str
    tokenType: str = "Bearer"
    expiresInSeconds: int


@app.post("/auth/sessions", response_model=SessionResponse, tags=["auth"])
async def create_browser_session(payload: SessionCreateRequest, response: Response) -> SessionResponse:
    if settings.environment not in {"development", "test"}:
        raise HTTPException(503, "OIDC_BFF_NOT_CONFIGURED")
    session_token = secrets.token_urlsafe(32)
    csrf_secret = secrets.token_urlsafe(32)
    session_public_id = public_id("ses")
    async with transaction(workspace_id=payload.workspaceId) as connection:
        record = await session_store.create_session(
            connection,
            public_id=session_public_id,
            principal_id=payload.principalId,
            workspace_id=payload.workspaceId,
            session_token=session_token,
            csrf_secret=csrf_secret,
        )
        await write_audit_event(
            connection,
            workspace_id=payload.workspaceId,
            actor_id=str(payload.principalId),
            action="auth.session.created",
            resource_type="browser_session",
            resource_id=session_public_id,
            details={"authorizationGeneration": record.authorization_generation},
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
        workspaceId=payload.workspaceId,
        authorizationGeneration=record.authorization_generation,
        expiresAt=record.absolute_expires_at,
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
