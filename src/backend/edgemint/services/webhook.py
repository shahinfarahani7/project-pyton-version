from __future__ import annotations

from typing import Any

from fastapi import Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, HttpUrl

from edgemint.building_blocks.app import create_service_app
from edgemint.webhooks.engine import evaluate_delivery
from edgemint.webhooks.errors import WebhookServiceError
from edgemint.webhooks.policy import load_webhook_policy
from edgemint.webhooks.service import WebhookService

app = create_service_app("webhook")
webhook_service = WebhookService()


class CreateEndpointRequest(BaseModel):
    idempotencyKey: str
    workspaceId: str
    ownerId: str
    url: HttpUrl
    events: list[str] = Field(min_length=1)


class EnqueueDeliveryRequest(BaseModel):
    endpointId: str
    domainEventId: str
    eventType: str
    payload: dict[str, Any]


class RecordAttemptRequest(BaseModel):
    deliveryId: str
    httpStatus: int
    jitterSeed: int = 0


class ReplayDeliveryRequest(BaseModel):
    deliveryId: str
    requesterId: str
    authorized: bool = True


class EvaluateDeliveryRequest(BaseModel):
    httpStatus: int
    attempt: int = Field(ge=1)


@app.exception_handler(WebhookServiceError)
async def webhook_service_error_handler(_: Request, exc: WebhookServiceError) -> JSONResponse:
    return JSONResponse(
        {
            "type": f"https://problems.edgemint.io/{exc.code.lower().replace('_', '-')}",
            "title": exc.title,
            "status": exc.status,
            "code": exc.code,
            **({"detail": exc.detail} if exc.detail else {}),
        },
        status_code=exc.status,
    )


@app.get("/internal/webhook/policy", tags=["webhook"])
async def webhook_policy() -> JSONResponse:
    policy = load_webhook_policy()
    return JSONResponse({"policyVersion": policy.path.name, "spec": policy.spec}, status_code=200)


@app.post("/internal/webhook/delivery:evaluate", tags=["webhook"])
async def evaluate_delivery_route(payload: EvaluateDeliveryRequest) -> JSONResponse:
    return JSONResponse(
        evaluate_delivery({"httpStatus": payload.httpStatus, "attempt": payload.attempt}),
        status_code=200,
    )


@app.post("/internal/webhook/endpoints", tags=["webhook"])
async def create_endpoint(payload: CreateEndpointRequest) -> JSONResponse:
    endpoint = webhook_service.create_endpoint(
        idempotency_key=payload.idempotencyKey,
        workspace_id=payload.workspaceId,
        owner_id=payload.ownerId,
        url=str(payload.url),
        events=payload.events,
    )
    return JSONResponse(
        {
            "endpointId": endpoint.endpoint_id,
            "workspaceId": endpoint.workspace_id,
            "url": endpoint.url,
            "events": endpoint.events,
            "enabled": endpoint.enabled,
        },
        status_code=201,
    )


@app.post("/internal/webhook/endpoints/{endpoint_id}:rotate-secret", tags=["webhook"])
async def rotate_secret(endpoint_id: str) -> JSONResponse:
    endpoint = webhook_service.rotate_secret(endpoint_id=endpoint_id)
    return JSONResponse(
        {
            "endpointId": endpoint.endpoint_id,
            "rotatedAt": endpoint.secret_rotated_at.isoformat() if endpoint.secret_rotated_at else None,
            "overlapHours": load_webhook_policy().spec["signature"]["secretOverlapHours"],
        },
        status_code=200,
    )


@app.post("/internal/webhook/endpoints/{endpoint_id}:disable", tags=["webhook"])
async def disable_endpoint(endpoint_id: str) -> JSONResponse:
    endpoint = webhook_service.disable_endpoint(endpoint_id=endpoint_id)
    return JSONResponse({"endpointId": endpoint.endpoint_id, "enabled": endpoint.enabled}, status_code=200)


@app.post("/internal/webhook/deliveries:enqueue", tags=["webhook"])
async def enqueue_delivery(payload: EnqueueDeliveryRequest) -> JSONResponse:
    delivery = webhook_service.enqueue_delivery(
        endpoint_id=payload.endpointId,
        domain_event_id=payload.domainEventId,
        event_type=payload.eventType,
        payload=payload.payload,
    )
    if delivery is None:
        return JSONResponse({"accepted": False}, status_code=202)
    return JSONResponse(
        {
            "deliveryId": delivery.delivery_id,
            "domainEventId": delivery.domain_event_id,
            "status": delivery.status,
        },
        status_code=202,
    )


@app.post("/internal/webhook/deliveries:record-attempt", tags=["webhook"])
async def record_attempt(payload: RecordAttemptRequest) -> JSONResponse:
    delivery = webhook_service.record_delivery_attempt(
        delivery_id=payload.deliveryId,
        http_status=payload.httpStatus,
        jitter_seed=payload.jitterSeed,
    )
    last = delivery.attempts[-1]
    return JSONResponse(
        {
            "deliveryId": delivery.delivery_id,
            "status": delivery.status,
            "attempt": {
                "attemptNumber": last.attempt_number,
                "success": last.success,
                "retry": last.retry,
                "baseDelaySeconds": last.base_delay_seconds,
                "scheduledDelaySeconds": last.scheduled_delay_seconds,
                "terminal": last.terminal,
            },
        },
        status_code=200,
    )


@app.post("/internal/webhook/deliveries:replay", tags=["webhook"])
async def replay_delivery(payload: ReplayDeliveryRequest) -> JSONResponse:
    replay = webhook_service.replay_delivery(
        delivery_id=payload.deliveryId,
        requester_id=payload.requesterId,
        authorized=payload.authorized,
    )
    return JSONResponse(
        {
            "deliveryId": replay.delivery_id,
            "domainEventId": replay.domain_event_id,
            "replayOfDeliveryId": replay.replay_of_delivery_id,
            "status": replay.status,
        },
        status_code=201,
    )


@app.get("/internal/webhook/metrics", tags=["webhook"])
async def delivery_metrics() -> JSONResponse:
    return JSONResponse(webhook_service.delivery_metrics(), status_code=200)


@app.get("/internal/webhook/dead-letter", tags=["webhook"])
async def dead_letter_queue() -> JSONResponse:
    return JSONResponse({"deliveryIds": list(webhook_service.dead_letter)}, status_code=200)
