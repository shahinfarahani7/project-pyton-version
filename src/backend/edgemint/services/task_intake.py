from __future__ import annotations

from typing import Annotated

from fastapi import Depends, Header, Request
from fastapi.responses import JSONResponse

from edgemint.building_blocks.app import create_service_app
from edgemint.building_blocks.database import transaction
from edgemint.security.context import AuthorizationContext
from edgemint.security.dependencies import AuthorizationDependency
from edgemint.security.problems import request_trace_id
from edgemint.tasks.admission import TaskAdmissionService
from edgemint.tasks.errors import TaskServiceError
from edgemint.tasks.schemas import CreateRevisionRequest, CreateTaskRequest

app = create_service_app("task-intake")
admission = TaskAdmissionService()

CreateTaskAuth = Annotated[
    AuthorizationContext,
    Depends(AuthorizationDependency("createTask")),
]
CreateRevisionAuth = Annotated[
    AuthorizationContext,
    Depends(AuthorizationDependency("createTaskRevision")),
]
CancelTaskAuth = Annotated[
    AuthorizationContext,
    Depends(AuthorizationDependency("cancelTask")),
]
GetTaskAuth = Annotated[
    AuthorizationContext,
    Depends(AuthorizationDependency("getTask")),
]


@app.exception_handler(TaskServiceError)
async def task_service_error_handler(_: Request, exc: TaskServiceError) -> JSONResponse:
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


@app.post("/tasks", tags=["tasks"])
async def create_task(
    request: Request,
    payload: CreateTaskRequest,
    auth: CreateTaskAuth,
    idempotency_key: str = Header(alias="Idempotency-Key"),
) -> JSONResponse:
    async with transaction(workspace_id=auth.workspace_id, isolation="SERIALIZABLE") as connection:
        body = await admission.create_task(
            connection,
            auth=auth,
            payload=payload,
            idempotency_key=idempotency_key,
        )
    response = JSONResponse(body.model_dump(mode="json"), status_code=202)
    response.headers["X-Request-Id"] = request_trace_id(request)
    return response


@app.get("/tasks/{task_id}", tags=["tasks"])
async def get_task(task_id: str, auth: GetTaskAuth) -> JSONResponse:
    async with transaction(workspace_id=auth.workspace_id, isolation="READ COMMITTED") as connection:
        body = await admission.get_task(connection, auth=auth, task_public_id=task_id)
    return JSONResponse(body.model_dump(mode="json"), status_code=200)


@app.post("/tasks/{task_id}:cancel", tags=["tasks"])
async def cancel_task(
    task_id: str,
    auth: CancelTaskAuth,
    idempotency_key: str = Header(alias="Idempotency-Key"),
) -> JSONResponse:
    async with transaction(workspace_id=auth.workspace_id, isolation="READ COMMITTED") as connection:
        body = await admission.cancel_task(
            connection,
            auth=auth,
            task_public_id=task_id,
            idempotency_key=idempotency_key,
        )
    return JSONResponse(body.model_dump(mode="json"), status_code=202)


@app.post("/tasks/{task_id}/revisions", tags=["tasks"])
async def create_task_revision(
    task_id: str,
    payload: CreateRevisionRequest,
    auth: CreateRevisionAuth,
    idempotency_key: str = Header(alias="Idempotency-Key"),
) -> JSONResponse:
    async with transaction(workspace_id=auth.workspace_id, isolation="READ COMMITTED") as connection:
        body = await admission.create_revision(
            connection,
            auth=auth,
            task_public_id=task_id,
            payload=payload,
            idempotency_key=idempotency_key,
        )
    return JSONResponse(body.model_dump(mode="json"), status_code=202)
