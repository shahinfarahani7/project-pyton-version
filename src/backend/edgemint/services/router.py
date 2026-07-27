from __future__ import annotations

from typing import Any

from fastapi import Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from edgemint.building_blocks.app import create_service_app
from edgemint.routing.errors import RouterServiceError
from edgemint.routing.service import RouterService

app = create_service_app("router")
router_service = RouterService()


class EvaluateCandidateRequest(BaseModel):
    input: dict[str, Any]


class RankWorkersRequest(BaseModel):
    taskId: str
    routerEpoch: int = Field(ge=0)
    candidates: list[dict[str, Any]]


@app.exception_handler(RouterServiceError)
async def router_service_error_handler(_: Request, exc: RouterServiceError) -> JSONResponse:
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


@app.get("/router/policy", tags=["router"])
async def get_routing_policy() -> JSONResponse:
    return JSONResponse(
        {
            "assignmentMode": router_service.policy.assignment_mode,
            "perTaskWorkerConfirmation": router_service.policy.per_task_worker_confirmation,
            "deliveryAckMeaning": router_service.policy.delivery_ack_meaning,
            "maxWorkerReassignments": router_service.policy.max_worker_reassignments,
        },
        status_code=200,
    )


@app.post("/internal/router/evaluate", tags=["router"])
async def evaluate_candidate(payload: EvaluateCandidateRequest) -> JSONResponse:
    body = router_service.evaluate(payload.input)
    return JSONResponse(body, status_code=200)


@app.post("/internal/router/rank", tags=["router"])
async def rank_workers(payload: RankWorkersRequest) -> JSONResponse:
    body = router_service.rank_workers(
        task_id=payload.taskId,
        router_epoch=payload.routerEpoch,
        candidates=payload.candidates,
    )
    return JSONResponse(body, status_code=200)
