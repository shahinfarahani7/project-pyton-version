from __future__ import annotations

import asyncio
import json
import logging
from datetime import UTC, datetime, timedelta
from uuid import UUID

from fastapi import HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.building_blocks.app import create_service_app
from edgemint.building_blocks.database import transaction
from edgemint.building_blocks.eventing.relay import (
    claim_deliveries,
    create_subscription,
    open_connection,
    resume_connection,
)
from edgemint.building_blocks.eventing.transactional_inbox import InboxRecord, record_inbox_before_ack
from edgemint.building_blocks.eventing.transactional_outbox import cloud_event_payload_sha256
from edgemint.building_blocks.ids import public_id
from edgemint.building_blocks.settings import get_settings
from edgemint.security.tokens import DelegatedTokenService

app = create_service_app("event-relay")
settings = get_settings()
token_service = DelegatedTokenService(settings)
logger = logging.getLogger(__name__)


class HelloFrame(BaseModel):
    type: str
    requestId: str = Field(min_length=4, max_length=64)
    clientId: str = Field(min_length=1, max_length=128)
    clientVersion: str = Field(min_length=1, max_length=64)
    resumeToken: str | None = Field(default=None, max_length=256)


class SubscribeFrame(BaseModel):
    type: str
    requestId: str
    subscriptionId: str
    eventTypes: list[str]
    workspaceId: str | None = None
    fromSequence: int | None = None


def _auth_context_from_headers(websocket: WebSocket) -> tuple[UUID, UUID | None]:
    authorization = websocket.headers.get("authorization")
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "AUTHENTICATION_REQUIRED")

    if settings.allow_insecure_development_tokens and settings.environment in {"development", "test"}:
        try:
            principal_id = UUID(authorization.removeprefix("Bearer ").strip())
        except ValueError as exc:
            raise HTTPException(401, "INVALID_DEVELOPMENT_TOKEN") from exc
        workspace_header = websocket.headers.get("x-workspace-id")
        workspace_id = UUID(workspace_header) if workspace_header else None
        return principal_id, workspace_id

    try:
        claims = token_service.verify(authorization.removeprefix("Bearer ").strip())
    except Exception as exc:
        raise HTTPException(401, "INVALID_DELEGATED_TOKEN") from exc
    return claims.principal_id, claims.workspace_id


async def _subscription_public_id(connection: AsyncConnection, delivery_id: UUID) -> str:
    row = (
        await connection.execute(
            text(
                """
                SELECT subscription.public_id
                FROM public.websocket_deliveries AS delivery
                JOIN public.websocket_subscriptions AS subscription
                  ON subscription.id = delivery.subscription_id
                WHERE delivery.id = :delivery_id
                """
            ),
            {"delivery_id": delivery_id},
        )
    ).one_or_none()
    if row is None:
        raise ValueError("DELIVERY_NOT_FOUND")
    return str(row.public_id)


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


def _error_frame(request_id: str, code: str, message: str) -> dict[str, object]:
    return {
        "type": "error",
        "requestId": request_id,
        "code": code,
        "message": message,
        "retryable": False,
    }


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
        principal_id, workspace_id = _auth_context_from_headers(websocket)
    except HTTPException as exc:
        await websocket.close(code=1008, reason=str(exc.detail))
        return

    await websocket.accept(subprotocol="edgemint.events.v1")
    connection_id: UUID | None = None
    relay_instance_id = websocket.headers.get("x-relay-instance", "relay-local")
    owner_lease_seconds = settings.websocket_ack_timeout_seconds * 2
    try:
        hello = HelloFrame.model_validate(await websocket.receive_json())
        if hello.type != "hello":
            await websocket.close(code=1008, reason="INVALID_HELLO")
            return

        async with transaction(workspace_id=workspace_id, isolation="READ COMMITTED") as connection:
            if hello.resumeToken:
                connection_id, resume_token = await resume_connection(
                    connection,
                    principal_id=principal_id,
                    workspace_id=workspace_id,
                    client_id=hello.clientId,
                    client_version=hello.clientVersion,
                    resume_token=hello.resumeToken,
                    relay_instance_id=relay_instance_id,
                    owner_lease_seconds=owner_lease_seconds,
                )
            else:
                connection_id, resume_token = await open_connection(
                    connection,
                    principal_id=principal_id,
                    workspace_id=workspace_id,
                    client_id=hello.clientId,
                    client_version=hello.clientVersion,
                    relay_instance_id=relay_instance_id,
                    owner_lease_seconds=owner_lease_seconds,
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
            deliveries = await claim_deliveries(
                connection_id=connection_id,
                relay_instance_id=relay_instance_id,
                lease_seconds=settings.websocket_ack_timeout_seconds,
                max_in_flight=settings.websocket_max_in_flight,
            )
            for delivery in deliveries:
                delivery_id = UUID(str(delivery["delivery_id"]))
                async with transaction(isolation="READ COMMITTED") as connection:
                    subscription_public_id = await _subscription_public_id(connection, delivery_id)
                cloud_event = delivery["cloud_event_json"]
                if isinstance(cloud_event, str):
                    cloud_event = json.loads(cloud_event)
                await websocket.send_json(
                    {
                        "type": "event",
                        "requestId": public_id("req"),
                        "deliveryId": f"del_{delivery_id.hex}",
                        "subscriptionId": subscription_public_id,
                        "sequence": delivery["delivery_sequence"],
                        "cloudEvent": cloud_event,
                        "ackDeadlineUtc": (
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
            request_id = str(frame.get("requestId", public_id("req")))
            if frame_type == "subscribe":
                try:
                    subscribe = SubscribeFrame.model_validate(frame)
                except Exception:
                    await websocket.send_json(
                        _error_frame(request_id, "INVALID_SUBSCRIPTION", "Invalid subscribe frame")
                    )
                    continue
                if subscribe.workspaceId and UUID(subscribe.workspaceId) != workspace_id:
                    await websocket.send_json(
                        _error_frame(request_id, "WORKSPACE_MISMATCH", "Cross-workspace subscription denied")
                    )
                    continue
                async with transaction(workspace_id=workspace_id, isolation="READ COMMITTED") as connection:
                    subscription_id = await create_subscription(
                        connection,
                        connection_id=connection_id,
                        principal_id=principal_id,
                        workspace_id=workspace_id,
                        event_types=subscribe.eventTypes,
                    )
                    next_sequence = (
                        await connection.execute(
                            text("SELECT next_sequence FROM public.websocket_subscriptions WHERE id = :id"),
                            {"id": subscription_id},
                        )
                    ).scalar_one()
                await websocket.send_json(
                    {
                        "type": "subscribed",
                        "requestId": subscribe.requestId,
                        "subscriptionId": subscribe.subscriptionId,
                        "nextSequence": next_sequence,
                    }
                )
            elif frame_type == "ack":
                try:
                    delivery_id = UUID(str(frame["deliveryId"]).removeprefix("del_"))
                    sequence = int(frame["sequence"])
                    if sequence <= 0:
                        raise ValueError("sequence must be positive")
                except (KeyError, TypeError, ValueError):
                    await websocket.send_json(
                        _error_frame(request_id, "INVALID_ACK", "Invalid acknowledgement frame")
                    )
                    continue
                async with transaction(workspace_id=workspace_id, isolation="READ COMMITTED") as connection:
                    cloud_event_row = (
                        await connection.execute(
                            text(
                                """
                                SELECT event.id, event.event_type, event.cloud_event_json
                                FROM public.websocket_deliveries AS delivery
                                JOIN public.outbox_events AS event ON event.id = delivery.outbox_event_id
                                WHERE delivery.id = :delivery_id
                                """
                            ),
                            {"delivery_id": delivery_id},
                        )
                    ).one_or_none()
                    if cloud_event_row is None:
                        continue
                    payload = cloud_event_row.cloud_event_json
                    if isinstance(payload, str):
                        payload = json.loads(payload)
                    await record_inbox_before_ack(
                        connection,
                        inbox=InboxRecord(
                            consumer_name=f"relay:{connection_id}",
                            event_id=cloud_event_row.id,
                            event_type=cloud_event_row.event_type,
                            payload_sha256=cloud_event_payload_sha256(payload),
                        ),
                        delivery_id=delivery_id,
                        sequence=sequence,
                        principal_id=principal_id,
                    )
            elif frame_type == "pong":
                await _touch(connection_id, relay_instance_id)
            elif frame_type == "ping":
                await _touch(connection_id, relay_instance_id)
                await websocket.send_json(
                    {"type": "pong", "requestId": request_id, "sentAtUtc": datetime.now(UTC).isoformat()}
                )
            else:
                await websocket.send_json(
                    _error_frame(request_id, "UNSUPPORTED_FRAME_TYPE", "Unsupported frame type")
                )
    except (WebSocketDisconnect, asyncio.CancelledError):
        return
    except ValueError as exc:
        if str(exc) == "RESUME_TOKEN_INVALID":
            await websocket.close(code=1008, reason="RESUME_TOKEN_INVALID")
        raise
    finally:
        if connection_id is not None:
            try:
                await _close(connection_id, relay_instance_id)
            except Exception:
                logger.exception(
                    "websocket connection cleanup failed",
                    extra={"connection_id": str(connection_id)},
                )
