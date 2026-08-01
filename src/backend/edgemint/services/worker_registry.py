from __future__ import annotations

from fastapi import Header, Request
from fastapi.responses import JSONResponse, Response

from edgemint.building_blocks.app import create_service_app
from edgemint.building_blocks.database import transaction
from edgemint.security.problems import request_trace_id
from edgemint.workers.dependencies import WorkerBearerToken
from edgemint.workers.enrollment import WorkerEnrollmentService
from edgemint.workers.errors import WorkerServiceError
from edgemint.workers.schemas import (
    CreateChallengeRequest,
    DeviceRegistrationRequest,
    HeartbeatRequest,
    RefreshSessionRequest,
    ReplaceWorkerPreferencesRequest,
    SubmitBenchmarkRequest,
)

app = create_service_app("worker-registry")
enrollment = WorkerEnrollmentService()


@app.exception_handler(WorkerServiceError)
async def worker_service_error_handler(_: Request, exc: WorkerServiceError) -> JSONResponse:
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


@app.post("/auth/challenges", tags=["registration"], status_code=201)
async def create_device_challenge(
    request: Request,
    payload: CreateChallengeRequest,
    idempotency_key: str = Header(alias="Idempotency-Key"),
) -> JSONResponse:
    async with transaction(isolation="READ COMMITTED") as connection:
        body = await enrollment.create_device_challenge(
            connection,
            payload=payload,
            idempotency_key=idempotency_key,
        )
    response = JSONResponse(body.model_dump(mode="json"), status_code=201)
    response.headers["X-Request-Id"] = request_trace_id(request)
    return response


@app.post("/workers/register", tags=["registration"], status_code=201)
async def register_worker_device(
    request: Request,
    payload: DeviceRegistrationRequest,
    idempotency_key: str = Header(alias="Idempotency-Key"),
) -> JSONResponse:
    async with transaction(isolation="READ COMMITTED") as connection:
        body = await enrollment.register_worker_device(
            connection,
            payload=payload,
            idempotency_key=idempotency_key,
        )
    response = JSONResponse(body.model_dump(mode="json"), status_code=201)
    response.headers["X-Request-Id"] = request_trace_id(request)
    return response


@app.post("/sessions:refresh", tags=["registration"])
async def refresh_worker_session(
    request: Request,
    payload: RefreshSessionRequest,
    idempotency_key: str = Header(alias="Idempotency-Key"),
) -> JSONResponse:
    async with transaction(isolation="READ COMMITTED") as connection:
        body = await enrollment.refresh_worker_session(
            connection,
            payload=payload,
            idempotency_key=idempotency_key,
        )
    response = JSONResponse(body.model_dump(mode="json"), status_code=200)
    response.headers["X-Request-Id"] = request_trace_id(request)
    return response


@app.post("/workers/{worker_id}/benchmark", tags=["registration"])
async def submit_benchmark(
    request: Request,
    worker_id: str,
    payload: SubmitBenchmarkRequest,
    token: WorkerBearerToken,
    idempotency_key: str = Header(alias="Idempotency-Key"),
) -> JSONResponse:
    async with transaction(isolation="READ COMMITTED") as connection:
        body = await enrollment.submit_benchmark_for_session(
            connection,
            session_token=token,
            worker_public_id=worker_id,
            payload=payload,
            idempotency_key=idempotency_key,
            request_id=request_trace_id(request),
        )
    response = JSONResponse(body.model_dump(mode="json"), status_code=200)
    response.headers["X-Request-Id"] = request_trace_id(request)
    return response


@app.post("/workers/{worker_id}/heartbeat", tags=["health"])
async def send_heartbeat(
    request: Request,
    worker_id: str,
    payload: HeartbeatRequest,
    token: WorkerBearerToken,
    idempotency_key: str = Header(alias="Idempotency-Key"),
) -> JSONResponse:
    async with transaction(isolation="READ COMMITTED") as connection:
        body = await enrollment.send_heartbeat(
            connection,
            session_token=token,
            worker_public_id=worker_id,
            payload=payload,
            idempotency_key=idempotency_key,
            request_id=request_trace_id(request),
        )
    response = JSONResponse(body.model_dump(mode="json"), status_code=200)
    response.headers["X-Request-Id"] = request_trace_id(request)
    return response


@app.get("/worker-preferences", tags=["preferences"])
async def get_worker_preferences(token: WorkerBearerToken) -> JSONResponse:
    async with transaction(isolation="READ COMMITTED") as connection:
        body = await enrollment.get_worker_preferences(connection, session_token=token)
    return JSONResponse(body.model_dump(mode="json"), status_code=200)


@app.put("/worker-preferences", tags=["preferences"])
async def replace_worker_preferences(
    request: Request,
    payload: ReplaceWorkerPreferencesRequest,
    token: WorkerBearerToken,
    idempotency_key: str = Header(alias="Idempotency-Key"),
) -> JSONResponse:
    async with transaction(isolation="READ COMMITTED") as connection:
        body = await enrollment.replace_worker_preferences(
            connection,
            session_token=token,
            payload=payload,
            idempotency_key=idempotency_key,
            request_id=request_trace_id(request),
        )
    response = JSONResponse(body.model_dump(mode="json"), status_code=200)
    response.headers["X-Request-Id"] = request_trace_id(request)
    return response


def _dev_worker_assignments_enabled() -> bool:
    from edgemint.building_blocks.settings import get_settings

    return get_settings().environment in {"development", "test"}


if _dev_worker_assignments_enabled():
    from edgemint.dev import worker_assignments as dev_worker_assignments

    @app.get("/assignments:next", tags=["dev-assignments"])
    async def dev_next_assignment(token: WorkerBearerToken) -> JSONResponse:
        _ = token
        assignment = dev_worker_assignments.pop_next_assignment()
        if assignment is None:
            return Response(status_code=204)
        return JSONResponse(assignment, status_code=200)

    @app.post("/assignments/{assignment_id}:started", tags=["dev-assignments"])
    async def dev_assignment_started(
        assignment_id: str,
        token: WorkerBearerToken,
        idempotency_key: str = Header(alias="Idempotency-Key"),
    ) -> JSONResponse:
        _ = (assignment_id, token, idempotency_key)
        return JSONResponse(
            dev_worker_assignments.command_receipt("devAssignmentStarted"),
            status_code=200,
        )

    @app.post("/assignments/{assignment_id}:progress", tags=["dev-assignments"])
    async def dev_assignment_progress(
        assignment_id: str,
        token: WorkerBearerToken,
        idempotency_key: str = Header(alias="Idempotency-Key"),
    ) -> JSONResponse:
        _ = (assignment_id, token, idempotency_key)
        return JSONResponse(
            dev_worker_assignments.command_receipt("devAssignmentProgress"),
            status_code=200,
        )

    @app.post("/assignments/{assignment_id}:complete", tags=["dev-assignments"])
    async def dev_assignment_complete(
        assignment_id: str,
        token: WorkerBearerToken,
        idempotency_key: str = Header(alias="Idempotency-Key"),
    ) -> JSONResponse:
        _ = (token, idempotency_key)
        dev_worker_assignments.mark_completed(assignment_id)
        return JSONResponse(
            dev_worker_assignments.command_receipt("devAssignmentComplete"),
            status_code=200,
        )

    @app.post("/assignments/{assignment_id}:abandon", tags=["dev-assignments"])
    async def dev_assignment_abandon(
        assignment_id: str,
        token: WorkerBearerToken,
        idempotency_key: str = Header(alias="Idempotency-Key"),
    ) -> JSONResponse:
        _ = (assignment_id, token, idempotency_key)
        return JSONResponse(
            dev_worker_assignments.command_receipt("devAssignmentAbandon"),
            status_code=200,
        )
