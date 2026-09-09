from __future__ import annotations

import os

import httpx
from fastapi import Header, Request
from fastapi.responses import JSONResponse, Response

from edgemint.building_blocks.app import create_service_app
from edgemint.building_blocks.database import transaction
from edgemint.security.problems import request_trace_id
from edgemint.workers.dependencies import WorkerBearerToken
from edgemint.workers.enrollment import WorkerEnrollmentService
from edgemint.workers.errors import WorkerServiceError
from edgemint.workers.resource_policy import build_contribution_policy_view
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


@app.get("/workers/{worker_id}/calibration", tags=["registration"])
async def get_worker_calibration(
    request: Request,
    worker_id: str,
    token: WorkerBearerToken,
) -> JSONResponse:
    async with transaction(isolation="READ COMMITTED") as connection:
        body = await enrollment.get_worker_calibration(
            connection,
            session_token=token,
            worker_public_id=worker_id,
        )
    response = JSONResponse(body.model_dump(mode="json"), status_code=200)
    response.headers["X-Request-Id"] = request_trace_id(request)
    return response


@app.get("/policy/resource-contribution", tags=["policy"])
async def get_resource_contribution_policy(request: Request) -> JSONResponse:
    body = build_contribution_policy_view()
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


if not _dev_worker_assignments_enabled():
    from edgemint.workers.assignments import (
        AssignmentCommandService,
        AssignmentCredentialBootstrapService,
    )
    from pydantic import BaseModel, Field

    assignment_bootstrap = AssignmentCredentialBootstrapService()
    assignment_commands = AssignmentCommandService()

    class StartAssignmentRequest(BaseModel):
        leaseToken: str = Field(min_length=16, max_length=512)
        fenceToken: int = Field(ge=1)

    class RenewAssignmentRequest(StartAssignmentRequest):
        sequence: int = Field(ge=1)

    class CompleteAssignmentRequest(StartAssignmentRequest):
        resultSha256: str = Field(pattern=r"^[a-f0-9]{64}$")
        outputArtifactId: str = Field(min_length=1, max_length=128)
        outputInline: str = Field(min_length=1, max_length=2 * 1024 * 1024)
        signature: str = Field(min_length=16, max_length=512)
        metrics: dict = Field(default_factory=dict)

    class ProgressAssignmentRequest(StartAssignmentRequest):
        sequence: int = Field(ge=1)
        stage: str = Field(min_length=1, max_length=128)
        progressBps: int = Field(ge=0, le=10_000)
        metrics: dict | None = None

    class CheckpointAssignmentRequest(StartAssignmentRequest):
        sequence: int = Field(ge=1)
        modelVersionId: str = Field(min_length=1, max_length=128)
        inputSha256: str = Field(pattern=r"^[a-f0-9]{64}$")
        checkpointSha256: str = Field(pattern=r"^[a-f0-9]{64}$")
        encryptedBlobRef: str = Field(min_length=1, max_length=512)
        chunkIndex: int | None = Field(default=None, ge=0)

    class FailAssignmentRequest(StartAssignmentRequest):
        errorCode: str = Field(min_length=1, max_length=64)
        retryable: bool
        diagnostics: dict | None = None

    class ConfirmPhysicalStopRequest(StartAssignmentRequest):
        proof: str = Field(min_length=8, max_length=512)
        reason: str = Field(default="worker_stop_confirmed", min_length=1, max_length=128)

    @app.get("/assignments:inboxBootstrap", tags=["assignments"])
    async def assignment_inbox_bootstrap(token: WorkerBearerToken) -> JSONResponse:
        async with transaction(isolation="READ COMMITTED") as connection:
            body = await assignment_bootstrap.inbox_bootstrap(connection, access_token=token)
        response = JSONResponse(body, status_code=200)
        response.headers["Cache-Control"] = "no-store"
        return response

    @app.get("/assignments:next", tags=["assignments"])
    async def next_automatic_assignment(token: WorkerBearerToken) -> JSONResponse:
        async with transaction(isolation="READ COMMITTED") as connection:
            assignment = await assignment_bootstrap.next_assignment(
                connection,
                access_token=token,
            )
        if assignment is None:
            return Response(status_code=204)
        response = JSONResponse(assignment, status_code=200)
        response.headers["Cache-Control"] = "no-store"
        response.headers["Pragma"] = "no-cache"
        return response

    @app.post("/assignments/{assignment_id}:started", tags=["assignments"])
    async def start_automatic_assignment(
        assignment_id: str,
        payload: StartAssignmentRequest,
        token: WorkerBearerToken,
        idempotency_key: str = Header(alias="Idempotency-Key"),
    ) -> JSONResponse:
        _ = idempotency_key
        async with transaction(isolation="SERIALIZABLE") as connection:
            receipt = await assignment_commands.start(
                connection,
                access_token=token,
                assignment_id=assignment_id,
                lease_token=payload.leaseToken,
                fence_token=payload.fenceToken,
            )
        return JSONResponse(receipt, status_code=200)

    @app.post("/assignments/{assignment_id}:renew", tags=["assignments"])
    async def renew_automatic_assignment(
        assignment_id: str,
        payload: RenewAssignmentRequest,
        token: WorkerBearerToken,
        idempotency_key: str = Header(alias="Idempotency-Key"),
    ) -> JSONResponse:
        _ = idempotency_key
        async with transaction(isolation="SERIALIZABLE") as connection:
            receipt = await assignment_commands.renew(
                connection,
                access_token=token,
                assignment_id=assignment_id,
                lease_token=payload.leaseToken,
                fence_token=payload.fenceToken,
                sequence=payload.sequence,
            )
        return JSONResponse(receipt, status_code=200)

    @app.post("/assignments/{assignment_id}:complete", tags=["assignments"], status_code=202)
    async def complete_automatic_assignment(
        assignment_id: str,
        payload: CompleteAssignmentRequest,
        token: WorkerBearerToken,
        idempotency_key: str = Header(alias="Idempotency-Key"),
    ) -> JSONResponse:
        _ = idempotency_key
        async with transaction(isolation="SERIALIZABLE") as connection:
            receipt = await assignment_commands.complete(
                connection,
                access_token=token,
                assignment_id=assignment_id,
                lease_token=payload.leaseToken,
                fence_token=payload.fenceToken,
                result_sha256=payload.resultSha256,
                output_artifact_id=payload.outputArtifactId,
                output_inline=payload.outputInline,
                signature=payload.signature,
                metrics=payload.metrics,
            )
        return JSONResponse(receipt, status_code=202)

    @app.post("/assignments/{assignment_id}:progress", tags=["assignments"])
    async def progress_automatic_assignment(
        assignment_id: str,
        payload: ProgressAssignmentRequest,
        token: WorkerBearerToken,
        idempotency_key: str = Header(alias="Idempotency-Key"),
    ) -> JSONResponse:
        _ = idempotency_key
        async with transaction(isolation="SERIALIZABLE") as connection:
            receipt = await assignment_commands.progress(
                connection,
                access_token=token,
                assignment_id=assignment_id,
                lease_token=payload.leaseToken,
                fence_token=payload.fenceToken,
                sequence=payload.sequence,
                stage=payload.stage,
                progress_bps=payload.progressBps,
                metrics=payload.metrics,
            )
        return JSONResponse(receipt, status_code=200)

    @app.post("/assignments/{assignment_id}:checkpoint", tags=["assignments"])
    async def checkpoint_automatic_assignment(
        assignment_id: str,
        payload: CheckpointAssignmentRequest,
        token: WorkerBearerToken,
        idempotency_key: str = Header(alias="Idempotency-Key"),
    ) -> JSONResponse:
        _ = idempotency_key
        async with transaction(isolation="SERIALIZABLE") as connection:
            receipt = await assignment_commands.checkpoint(
                connection,
                access_token=token,
                assignment_id=assignment_id,
                lease_token=payload.leaseToken,
                fence_token=payload.fenceToken,
                sequence=payload.sequence,
                model_version_id=payload.modelVersionId,
                input_sha256=payload.inputSha256,
                checkpoint_sha256=payload.checkpointSha256,
                encrypted_blob_ref=payload.encryptedBlobRef,
                chunk_index=payload.chunkIndex,
            )
        return JSONResponse(receipt, status_code=200)

    @app.post("/assignments/{assignment_id}:fail", tags=["assignments"], status_code=202)
    async def fail_automatic_assignment(
        assignment_id: str,
        payload: FailAssignmentRequest,
        token: WorkerBearerToken,
        idempotency_key: str = Header(alias="Idempotency-Key"),
    ) -> JSONResponse:
        _ = idempotency_key
        async with transaction(isolation="SERIALIZABLE") as connection:
            receipt = await assignment_commands.fail(
                connection,
                access_token=token,
                assignment_id=assignment_id,
                lease_token=payload.leaseToken,
                fence_token=payload.fenceToken,
                error_code=payload.errorCode,
                retryable=payload.retryable,
                diagnostics=payload.diagnostics,
            )
        return JSONResponse(receipt, status_code=202)

    @app.post("/assignments/{assignment_id}:confirmStop", tags=["assignments"], status_code=200)
    async def confirm_assignment_physical_stop(
        assignment_id: str,
        payload: ConfirmPhysicalStopRequest,
        token: WorkerBearerToken,
        idempotency_key: str = Header(alias="Idempotency-Key"),
    ) -> JSONResponse:
        _ = idempotency_key
        async with transaction(isolation="SERIALIZABLE") as connection:
            receipt = await assignment_commands.confirm_physical_stop(
                connection,
                access_token=token,
                assignment_id=assignment_id,
                lease_token=payload.leaseToken,
                fence_token=payload.fenceToken,
                proof=payload.proof,
                reason=payload.reason,
            )
        return JSONResponse(receipt, status_code=200)


if _dev_worker_assignments_enabled():
    from edgemint.dev import worker_assignments as dev_worker_assignments
    from pydantic import BaseModel

    _API_GATEWAY = os.environ.get("EDGEMINT_API_GATEWAY_URL", "http://api-gateway:8080").rstrip("/")

    async def _sync_portal_tasks_to_worker_queue() -> None:
        try:
            async with httpx.AsyncClient(timeout=3.0) as client:
                await client.post(f"{_API_GATEWAY}/internal/dev/sync-worker-queue")
        except httpx.HTTPError:
            pass

    class DevEnqueueAssignmentRequest(BaseModel):
        taskId: str
        taskType: str

    @app.post("/internal/dev/assignments", tags=["dev-assignments"], status_code=201)
    async def dev_enqueue_assignment(payload: DevEnqueueAssignmentRequest) -> JSONResponse:
        body = dev_worker_assignments.enqueue_dev_assignment(
            task_id=payload.taskId,
            task_type=payload.taskType,
        )
        return JSONResponse(body, status_code=201)

    @app.get("/internal/dev/assignments", tags=["dev-assignments"])
    async def dev_list_assignments() -> JSONResponse:
        return JSONResponse(
            {"items": dev_worker_assignments.list_pending_assignments()},
            status_code=200,
        )

    async def _ensure_task_input(task_id: str, task_type: str) -> None:
        try:
            async with httpx.AsyncClient(timeout=3.0) as client:
                await client.post(
                    f"{_API_GATEWAY}/internal/dev/tasks/{task_id}/ensure-input",
                    json={"taskType": task_type},
                )
        except httpx.HTTPError:
            pass

    @app.get("/assignments:next", tags=["dev-assignments"])
    async def dev_next_assignment(token: WorkerBearerToken) -> JSONResponse:
        _ = token
        assignment = dev_worker_assignments.pop_next_assignment()
        if assignment is None:
            await _sync_portal_tasks_to_worker_queue()
            assignment = dev_worker_assignments.pop_next_assignment()
        if assignment is None:
            return Response(status_code=204)
        task_id = assignment.get("taskId") or assignment["assignmentId"]
        await _ensure_task_input(task_id, assignment["taskType"])
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

    @app.post("/assignments/{assignment_id}:checkpoint", tags=["dev-assignments"])
    async def dev_assignment_checkpoint(
        assignment_id: str,
        token: WorkerBearerToken,
        idempotency_key: str = Header(alias="Idempotency-Key"),
    ) -> JSONResponse:
        _ = (assignment_id, token, idempotency_key)
        return JSONResponse(
            dev_worker_assignments.command_receipt("devAssignmentCheckpoint"),
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

    @app.post("/assignments/{assignment_id}:fail", tags=["dev-assignments"])
    async def dev_assignment_fail(
        assignment_id: str,
        token: WorkerBearerToken,
        idempotency_key: str = Header(alias="Idempotency-Key"),
    ) -> JSONResponse:
        _ = (assignment_id, token, idempotency_key)
        return JSONResponse(
            dev_worker_assignments.command_receipt("devAssignmentFail"),
            status_code=202,
        )
