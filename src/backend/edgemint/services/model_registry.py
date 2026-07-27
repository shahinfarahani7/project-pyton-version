from __future__ import annotations

from typing import Annotated

from fastapi import Depends, Header, Request
from fastapi.responses import JSONResponse

from edgemint.building_blocks.app import create_service_app
from edgemint.building_blocks.database import transaction
from edgemint.models.errors import ModelServiceError
from edgemint.models.registry import ModelRegistryService
from edgemint.models.schemas import (
    ApproveModelRequest,
    CreateModelVersionRequest,
    ReportModelInstallRequest,
    RevokeModelRequest,
    RollbackModelRolloutRequest,
    StartModelRolloutRequest,
)
from edgemint.security.dependencies import AuthorizationDependency
from edgemint.security.context import AuthorizationContext
from edgemint.security.problems import request_trace_id
from edgemint.workers.dependencies import WorkerBearerToken

app = create_service_app("model-registry")
registry = ModelRegistryService()

ApproveModelAuth = Annotated[AuthorizationContext, Depends(AuthorizationDependency("approveModel"))]
StartRolloutAuth = Annotated[AuthorizationContext, Depends(AuthorizationDependency("startModelRollout"))]
RevokeModelAuth = Annotated[AuthorizationContext, Depends(AuthorizationDependency("revokeModel"))]
RollbackRolloutAuth = Annotated[
    AuthorizationContext,
    Depends(AuthorizationDependency("rollbackModelRollout")),
]


@app.exception_handler(ModelServiceError)
async def model_service_error_handler(_: Request, exc: ModelServiceError) -> JSONResponse:
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


@app.post("/internal/model-versions", tags=["models"], status_code=201)
async def create_model_version(payload: CreateModelVersionRequest) -> JSONResponse:
    async with transaction(isolation="READ COMMITTED") as connection:
        body = await registry.create_model_version(connection, payload=payload)
    return JSONResponse(body.model_dump(mode="json"), status_code=201)


@app.post("/models/{model_version_id}:approve", tags=["models"], status_code=202)
async def approve_model(
    request: Request,
    model_version_id: str,
    payload: ApproveModelRequest,
    auth: ApproveModelAuth,
    idempotency_key: str = Header(alias="Idempotency-Key"),
) -> JSONResponse:
    async with transaction(isolation="READ COMMITTED") as connection:
        body = await registry.approve_model(
            connection,
            auth=auth,
            model_version_public_id=model_version_id,
            payload=payload,
            idempotency_key=idempotency_key,
            request_id=request_trace_id(request),
        )
    response = JSONResponse(body.model_dump(mode="json"), status_code=202)
    response.headers["X-Request-Id"] = request_trace_id(request)
    return response


@app.get("/models/{model_version_id}/manifest", tags=["models"])
async def get_model_manifest(model_version_id: str, token: WorkerBearerToken) -> JSONResponse:
    async with transaction(isolation="READ COMMITTED") as connection:
        body = await registry.get_model_manifest(
            connection,
            session_token=token,
            model_version_public_id=model_version_id,
        )
    return JSONResponse(body.model_dump(mode="json"), status_code=200)


@app.post("/models/{model_version_id}:report-install", tags=["models"])
async def report_model_install(
    request: Request,
    model_version_id: str,
    payload: ReportModelInstallRequest,
    token: WorkerBearerToken,
    idempotency_key: str = Header(alias="Idempotency-Key"),
) -> JSONResponse:
    async with transaction(isolation="READ COMMITTED") as connection:
        body = await registry.report_model_install(
            connection,
            session_token=token,
            model_version_public_id=model_version_id,
            payload=payload,
            idempotency_key=idempotency_key,
            request_id=request_trace_id(request),
        )
    response = JSONResponse(body.model_dump(mode="json"), status_code=200)
    response.headers["X-Request-Id"] = request_trace_id(request)
    return response


@app.post("/model-rollouts", tags=["models"], status_code=202)
async def start_model_rollout(
    request: Request,
    payload: StartModelRolloutRequest,
    auth: StartRolloutAuth,
    idempotency_key: str = Header(alias="Idempotency-Key"),
) -> JSONResponse:
    async with transaction(isolation="READ COMMITTED") as connection:
        body = await registry.start_model_rollout(
            connection,
            auth=auth,
            payload=payload,
            idempotency_key=idempotency_key,
            request_id=request_trace_id(request),
        )
    response = JSONResponse(body.model_dump(mode="json"), status_code=202)
    response.headers["X-Request-Id"] = request_trace_id(request)
    return response


@app.post("/models/{model_version_id}:revoke", tags=["models"], status_code=202)
async def revoke_model(
    request: Request,
    model_version_id: str,
    payload: RevokeModelRequest,
    auth: RevokeModelAuth,
    idempotency_key: str = Header(alias="Idempotency-Key"),
) -> JSONResponse:
    async with transaction(isolation="READ COMMITTED") as connection:
        body = await registry.revoke_model(
            connection,
            auth=auth,
            model_version_public_id=model_version_id,
            payload=payload,
            idempotency_key=idempotency_key,
            request_id=request_trace_id(request),
        )
    response = JSONResponse(body.model_dump(mode="json"), status_code=202)
    response.headers["X-Request-Id"] = request_trace_id(request)
    return response


@app.post("/model-rollouts/{rollout_id}:rollback", tags=["models"], status_code=202)
async def rollback_model_rollout(
    request: Request,
    rollout_id: str,
    payload: RollbackModelRolloutRequest,
    auth: RollbackRolloutAuth,
    idempotency_key: str = Header(alias="Idempotency-Key"),
) -> JSONResponse:
    async with transaction(isolation="READ COMMITTED") as connection:
        body = await registry.rollback_model_rollout(
            connection,
            auth=auth,
            rollout_public_id=rollout_id,
            payload=payload,
            idempotency_key=idempotency_key,
            request_id=request_trace_id(request),
        )
    response = JSONResponse(body.model_dump(mode="json"), status_code=202)
    response.headers["X-Request-Id"] = request_trace_id(request)
    return response
