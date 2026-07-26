from __future__ import annotations

import asyncio
import hashlib
import logging
import secrets
from datetime import UTC, datetime, timedelta
from uuid import UUID

from fastapi import HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field
from sqlalchemy import text

from edgemint.building_blocks.app import create_service_app
from edgemint.building_blocks.database import transaction
from edgemint.building_blocks.ids import public_id
from edgemint.building_blocks.settings import get_settings

app = create_service_app("event-relay")
settings = get_settings()
logger = logging.getLogger(__name__)


class HelloFrame(BaseModel):
    type: str
    requestId: str = Field(min_length=4, max_length=64)
    clientId: str = Field(min_length=1, max_length=128)
    clientVersion: str = Field(min_length=1, max_length=64)
    resumeToken: str | None = Field(default=None, max_length=256)


def _principal_from_headers(websocket: WebSocket) -> UUID:
    authorization = websocket.headers.get("authorization")
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "AUTHENTICATION_REQUIRED")

    # Raw UUID bearer tokens exist only to support isolated local contract tests.
    # Staging and production must use the delegated-token verifier delivered by WP-040.
    if not settings.allow_insecure_development_tokens or settings.environment not in {"development", "test"}:
        raise HTTPException(503, "DELEGATED_TOKEN_VERIFIER_NOT_CONFIGURED")

    try:
        return UUID(authorization.removeprefix("Bearer ").strip())
    except ValueError as exc:
        raise HTTPException(401, "INVALID_DEVELOPMENT_TOKEN") from exc


def _workspace_from_headers(websocket: WebSocket) -> UUID | None:
    value = websocket.headers.get("x-workspace-id")
    if not value:
        return None
    try:
        return UUID(value)
    except ValueError as exc:
        raise HTTPException(400, "INVALID_WORKSPACE_ID") from exc


async def _open_connection(
    *, principal_id: UUID, workspace_id: UUID | None, hello: HelloFrame, relay_instance_id: str
) -> tuple[UUID, str]:
    resume_token = secrets.token_urlsafe(32)
    resume_hash = hashlib.sha256(resume_token.encode("utf-8")).digest()
    resume_expiry = datetime.now(UTC) + timedelta(days=30)
    async with transaction(isolation="READ COMMITTED") as connection:
        connection_id = (
            await connection.execute(
                text(
                    """
                    SELECT eventing.open_websocket_connection(
                        :public_id, :principal_id, :workspace_id, :client_id, :client_version,
                        :resume_hash, :resume_expiry, :relay_instance_id, :owner_lease_seconds
                    )
                    """
                ),
                {
                    "public_id": public_id("wsc"),
                    "principal_id": principal_id,
                    "workspace_id": workspace_id,
                    "client_id": hello.clientId,
                    "client_version": hello.clientVersion,
                    "resume_hash": resume_hash,
                    "resume_expiry": resume_expiry,
                    "relay_instance_id": relay_instance_id,
                    "owner_lease_seconds": settings.websocket_ack_timeout_seconds * 2,
                },
            )
        ).scalar_one()
    return connection_id, resume_token


async def _create_subscription(
    *, connection_id: UUID, principal_id: UUID, workspace_id: UUID | None, event_types: list[str]
) -> UUID:
    async with transaction(isolation="READ COMMITTED") as connection:
        return (
            await connection.execute(
                text(
                    """
                    SELECT eventing.create_websocket_subscription(
                        :public_id, :connection_id, :principal_id, :workspace_id, CAST(:event_types AS jsonb)
                    )
                    """
                ),
                {
                    "public_id": public_id("wss"),
                    "connection_id": connection_id,
                    "principal_id": principal_id,
                    "workspace_id": workspace_id,
                    "event_types": __import__("json").dumps(event_types),
                },
            )
        ).scalar_one()


async def _claim_deliveries(connection_id: UUID, owner: str) -> list[dict[str, object]]:
    async with transaction(isolation="READ COMMITTED") as connection:
        rows = (
            await connection.execute(
                text(
                    """
                    SELECT * FROM eventing.claim_websocket_deliveries(
                        :relay_instance_id, :connection_id, 64, :lease_seconds, :max_in_flight
                    )
                    """
                ),
                {
                    "relay_instance_id": owner,
                    "connection_id": connection_id,
                    "lease_seconds": settings.websocket_ack_timeout_seconds,
                    "max_in_flight": settings.websocket_max_in_flight,
                },
            )
        ).mappings().all()
        return [dict(row) for row in rows]


async def _mark_sent(delivery_id: UUID, owner: str) -> None:
    async with transaction(isolation="READ COMMITTED") as connection:
        await connection.execute(
            text("SELECT eventing.mark_websocket_delivery_sent(:id, :owner, :ack_timeout)"),
            {"id": delivery_id, "owner": owner, "ack_timeout": settings.websocket_ack_timeout_seconds},
        )


async def _touch(connection_id: UUID, owner: str) -> None:
    async with transaction(isolation="READ COMMITTED") as connection:
        await connection.execute(
            text("SELECT eventing.touch_websocket_connection(:id, :owner, :lease_seconds)"),
            {
                "id": connection_id,
                "owner": owner,
                "lease_seconds": settings.websocket_ack_timeout_seconds * 2,
            },
        )


async def _close(connection_id: UUID, owner: str) -> None:
    async with transaction(isolation="READ COMMITTED") as connection:
        await connection.execute(
            text("SELECT eventing.close_websocket_connection(:id, :owner)"),
            {"id": connection_id, "owner": owner},
        )


@app.websocket("/events/v1")
async def events(websocket: WebSocket) -> None:
    if websocket.headers.get("origin"):
        await websocket.close(code=1008, reason="BROWSER_CLIENT_MUST_USE_BFF")
        return
    offered = websocket.headers.get("sec-websocket-protocol", "")
    if "edgemint.events.v1" not in {item.strip() for item in offered.split(",")}:
        await websocket.close(code=1002, reason="SUBPROTOCOL_REQUIRED")
        return

    try:
        principal_id = _principal_from_headers(websocket)
        workspace_id = _workspace_from_headers(websocket)
    except HTTPException as exc:
        await websocket.close(code=1008, reason=str(exc.detail))
        return

    await websocket.accept(subprotocol="edgemint.events.v1")
    connection_id: UUID | None = None
    relay_instance_id = websocket.headers.get("x-relay-instance", "relay-local")
    try:
        hello = HelloFrame.model_validate(await websocket.receive_json())
        if hello.type != "hello":
            await websocket.close(code=1008, reason="INVALID_HELLO")
            return
        if hello.resumeToken is not None:
            # Never silently downgrade a requested resume into a fresh connection.
            # WP-045 must implement token rotation and durable sequence restoration first.
            await websocket.close(code=1013, reason="RESUME_REQUIRES_WP_045")
            return

        connection_id, resume_token = await _open_connection(
            principal_id=principal_id,
            workspace_id=workspace_id,
            hello=hello,
            relay_instance_id=relay_instance_id,
        )
        await websocket.send_json(
            {
                "type": "welcome",
                "requestId": hello.requestId,
                "connectionId": str(connection_id),
                "resumeToken": resume_token,
                "heartbeatSeconds": settings.websocket_heartbeat_seconds,
                "maxInFlight": settings.websocket_max_in_flight,
            }
        )

        while True:
            deliveries = await _claim_deliveries(connection_id, relay_instance_id)
            for delivery in deliveries:
                delivery_id = UUID(str(delivery["delivery_id"]))
                await websocket.send_json(
                    {
                        "type": "event",
                        "requestId": public_id("req"),
                        "deliveryId": str(delivery_id),
                        "sequence": delivery["delivery_sequence"],
                        "event": delivery["cloud_event_json"],
                        "ackDeadlineAtUtc": (
                            datetime.now(UTC) + timedelta(seconds=settings.websocket_ack_timeout_seconds)
                        ).isoformat(),
                    }
                )
                await _mark_sent(delivery_id, relay_instance_id)

            try:
                frame = await asyncio.wait_for(websocket.receive_json(), timeout=0.25)
            except TimeoutError:
                continue

            frame_type = frame.get("type")
            if frame_type == "subscribe":
                event_types = frame.get("eventTypes")
                if not isinstance(event_types, list) or not all(isinstance(item, str) for item in event_types):
                    await websocket.send_json({"type": "error", "code": "INVALID_SUBSCRIPTION"})
                    continue
                subscription_id = await _create_subscription(
                    connection_id=connection_id,
                    principal_id=principal_id,
                    workspace_id=workspace_id,
                    event_types=event_types,
                )
                await websocket.send_json(
                    {
                        "type": "subscribed",
                        "requestId": frame.get("requestId"),
                        "subscriptionId": str(subscription_id),
                    }
                )
            elif frame_type == "ack":
                try:
                    delivery_id = UUID(str(frame["deliveryId"]))
                    sequence = int(frame["sequence"])
                    if sequence <= 0:
                        raise ValueError("sequence must be positive")
                except (KeyError, TypeError, ValueError):
                    await websocket.send_json({"type": "error", "code": "INVALID_ACK"})
                    continue
                async with transaction(isolation="READ COMMITTED") as connection:
                    await connection.execute(
                        text("SELECT eventing.acknowledge_delivery(:id, :sequence, :principal_id)"),
                        {
                            "id": delivery_id,
                            "sequence": sequence,
                            "principal_id": principal_id,
                        },
                    )
            elif frame_type == "pong":
                await _touch(connection_id, relay_instance_id)
            elif frame_type == "ping":
                await _touch(connection_id, relay_instance_id)
                await websocket.send_json({"type": "pong", "sentAtUtc": datetime.now(UTC).isoformat()})
            else:
                await websocket.send_json({"type": "error", "code": "UNSUPPORTED_FRAME_TYPE"})
    except (WebSocketDisconnect, asyncio.CancelledError):
        return
    finally:
        if connection_id is not None:
            try:
                await _close(connection_id, relay_instance_id)
            except Exception:
                # Connection cleanup is reconciled by lease expiry if the database is unavailable.
                logger.exception("websocket connection cleanup failed", extra={"connection_id": str(connection_id)})
