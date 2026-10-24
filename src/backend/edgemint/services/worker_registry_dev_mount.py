"""Dev assignment routes for slim worker-registry images (local Docker hot-mount)."""

from __future__ import annotations

import os

import httpx
from fastapi import Body, Header
from fastapi.responses import JSONResponse, Response

from edgemint.building_blocks.database import transaction
from edgemint.workers.dependencies import WorkerBearerToken
from pydantic import BaseModel


class DevEnqueueAssignmentRequest(BaseModel):
    taskId: str
    taskType: str


class DevFailAssignmentRequest(BaseModel):
    errorCode: str = "WORKER_EXECUTION_FAILED"
    retryable: bool = True
    diagnostics: dict | None = None


def _dev_worker_assignments_enabled() -> bool:
    from edgemint.building_blocks.settings import get_settings

    return get_settings().environment in {"development", "test"}


def mount_dev_routes(app) -> None:
    if not _dev_worker_assignments_enabled():
        return

    from edgemint.dev import worker_assignments as dev_worker_assignments

    _API_GATEWAY = os.environ.get("EDGEMINT_API_GATEWAY_URL", "http://api-gateway:8080").rstrip("/")

    async def _sync_portal_tasks_to_worker_queue() -> None:
        try:
            async with httpx.AsyncClient(timeout=3.0) as client:
                await client.post(f"{_API_GATEWAY}/internal/dev/sync-worker-queue")
        except httpx.HTTPError:
            pass

    @app.post("/internal/dev/assignments", tags=["dev-assignments"], status_code=201)
    async def dev_enqueue_assignment(
        payload: DevEnqueueAssignmentRequest = Body(),
    ) -> JSONResponse:
        assignment = dev_worker_assignments.enqueue_dev_assignment(
            task_id=payload.taskId,
            task_type=payload.taskType,
        )
        return JSONResponse(assignment, status_code=201)

    @app.get("/internal/dev/assignments", tags=["dev-assignments"])
    async def dev_list_assignments() -> JSONResponse:
        return JSONResponse(
            dev_worker_assignments.dev_assignment_state(),
            status_code=200,
        )

    @app.post(
        "/internal/dev/clear-exclusive-device-pin",
        tags=["dev-assignments"],
        status_code=204,
    )
    async def dev_clear_exclusive_device_pin() -> Response:
        dev_worker_assignments.clear_runtime_exclusive_device_pin()
        return Response(status_code=204)

    @app.delete(
        "/internal/dev/assignments/{assignment_id}",
        tags=["dev-assignments"],
        status_code=204,
    )
    async def dev_cancel_assignment(assignment_id: str) -> Response:
        dev_worker_assignments.cancel_dev_assignment(assignment_id)
        return Response(status_code=204)

    @app.get(
        "/assignments/{assignment_id}/cancellation",
        tags=["dev-assignments"],
    )
    async def dev_assignment_cancellation(
        assignment_id: str,
        token: WorkerBearerToken,
    ) -> JSONResponse:
        if not token:
            return JSONResponse(
                {"assignmentId": assignment_id, "cancelled": False},
                status_code=200,
            )
        return JSONResponse(
            {
                "assignmentId": assignment_id,
                "cancelled": dev_worker_assignments.is_assignment_cancelled(assignment_id),
            },
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

    @app.get("/assignments:inboxBootstrap", tags=["dev-assignments"])
    async def dev_assignment_inbox_bootstrap(token: WorkerBearerToken) -> JSONResponse:
        from edgemint.workers.sessions import resolve_worker_session

        async with transaction(isolation="READ COMMITTED") as connection:
            session = await resolve_worker_session(connection, access_token=token)
        response = JSONResponse(
            {
                "workerDeviceId": str(session.device_id),
                "deliveries": [],
            },
            status_code=200,
        )
        response.headers["Cache-Control"] = "no-store"
        return response

    @app.get("/assignments:next", tags=["dev-assignments"], response_model=None)
    async def dev_next_assignment(
        token: WorkerBearerToken,
        claim_assignments: str | None = Header(
            default=None,
            alias="X-EdgeMint-Dev-Claim-Assignments",
        ),
    ):
        from edgemint.workers.sessions import resolve_worker_session

        device_public_id: str | None = None
        try:
            async with transaction(isolation="READ COMMITTED") as connection:
                session = await resolve_worker_session(connection, access_token=token)
            device_public_id = session.device_public_id
        except Exception:
            pass

        claim_exclusive = claim_assignments == "1"
        assignment = dev_worker_assignments.claim_next_assignment(
            device_public_id=device_public_id,
            claim_exclusive=claim_exclusive,
        )
        if assignment is None:
            await _sync_portal_tasks_to_worker_queue()
            assignment = dev_worker_assignments.claim_next_assignment(
                device_public_id=device_public_id,
                claim_exclusive=claim_exclusive,
            )
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

    @app.post("/assignments/{assignment_id}:confirmStop", tags=["dev-assignments"])
    async def dev_assignment_confirm_stop(
        assignment_id: str,
        token: WorkerBearerToken,
        idempotency_key: str = Header(alias="Idempotency-Key"),
    ) -> JSONResponse:
        _ = (assignment_id, token, idempotency_key)
        return JSONResponse(
            dev_worker_assignments.command_receipt("devAssignmentConfirmStop"),
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

    async def _notify_portal_task_failed(task_id: str, error_code: str) -> None:
        try:
            async with httpx.AsyncClient(timeout=3.0) as client:
                response = await client.post(
                    f"{_API_GATEWAY}/internal/dev/tasks/{task_id}/fail",
                    json={"errorCode": error_code, "detail": error_code},
                )
                if response.status_code < 300:
                    return
        except httpx.HTTPError:
            pass
        from edgemint.dev import fixtures

        fixtures.reject_dev_task_output(
            task_id,
            reason_code=error_code,
            reason_detail=error_code,
        )

    @app.post("/assignments/{assignment_id}:fail", tags=["dev-assignments"])
    async def dev_assignment_fail(
        assignment_id: str,
        token: WorkerBearerToken,
        payload: DevFailAssignmentRequest,
        idempotency_key: str = Header(alias="Idempotency-Key"),
    ) -> JSONResponse:
        _ = idempotency_key
        from edgemint.workers.sessions import resolve_worker_session

        device_public_id: str | None = None
        try:
            async with transaction(isolation="READ COMMITTED") as connection:
                session = await resolve_worker_session(connection, access_token=token)
            device_public_id = session.device_public_id
        except Exception:
            device_public_id = None

        task_id = assignment_id
        terminal = dev_worker_assignments.record_worker_failure(
            task_id=task_id,
            device_id=device_public_id,
            error_code=payload.errorCode,
        )
        if terminal:
            await _notify_portal_task_failed(task_id, payload.errorCode)
        return JSONResponse(
            dev_worker_assignments.command_receipt("devAssignmentFail"),
            status_code=202,
        )
