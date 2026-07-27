from __future__ import annotations

from typing import Annotated

from fastapi import Depends, Header, HTTPException, Request, Response
from fastapi.responses import JSONResponse

from edgemint.building_blocks.app import create_service_app
from edgemint.building_blocks.database import transaction
from edgemint.building_blocks.settings import get_settings
from edgemint.files.errors import FileServiceError
from edgemint.files.lifecycle import FileLifecycleService
from edgemint.files.schemas import CompleteUploadRequest, UploadIntentRequest
from edgemint.security.context import AuthorizationContext
from edgemint.security.dependencies import AuthorizationDependency
from edgemint.security.problems import request_trace_id

app = create_service_app("file")
settings = get_settings()
lifecycle = FileLifecycleService(settings=settings)

CreateUploadIntentAuth = Annotated[
    AuthorizationContext,
    Depends(AuthorizationDependency("createUploadIntent")),
]
CompleteFileUploadAuth = Annotated[
    AuthorizationContext,
    Depends(AuthorizationDependency("completeFileUpload")),
]
GetFileAuth = Annotated[AuthorizationContext, Depends(AuthorizationDependency("getFile"))]
DeleteFileAuth = Annotated[AuthorizationContext, Depends(AuthorizationDependency("deleteFile"))]


@app.exception_handler(FileServiceError)
async def file_service_error_handler(_: Request, exc: FileServiceError) -> JSONResponse:
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


def _problem_from_http(exc: HTTPException) -> JSONResponse:
    if isinstance(exc.detail, dict):
        detail = exc.detail
    else:
        detail = {"code": "UNEXPECTED_ERROR", "title": str(exc.detail)}
    code = detail.get("code", "unexpected-error")
    return JSONResponse(
        {
            "type": f"https://problems.edgemint.io/{str(code).lower().replace('_', '-')}",
            "title": detail.get("title", "Request failed"),
            "status": exc.status_code,
            "code": detail.get("code", "UNEXPECTED_ERROR"),
            **({"detail": detail["detail"]} if detail.get("detail") else {}),
        },
        status_code=exc.status_code,
    )


@app.exception_handler(HTTPException)
async def http_exception_handler(_: Request, exc: HTTPException) -> JSONResponse:
    return _problem_from_http(exc)


@app.post("/files/upload-intents", response_model=None, status_code=201, tags=["files"])
async def create_upload_intent(
    request: Request,
    payload: UploadIntentRequest,
    response: Response,
    auth: CreateUploadIntentAuth,
    idempotency_key: str = Header(alias="Idempotency-Key"),
) -> JSONResponse:
    async with transaction(workspace_id=auth.workspace_id, isolation="READ COMMITTED") as connection:
        body = await lifecycle.create_upload_intent(
            connection,
            auth=auth,
            payload=payload,
            idempotency_key=idempotency_key,
        )
    response.headers["X-Request-Id"] = request_trace_id(request)
    return JSONResponse(body.model_dump(mode="json"), status_code=201)


@app.post("/files/{file_id}:complete", tags=["files"])
async def complete_file_upload(
    file_id: str,
    payload: CompleteUploadRequest,
    auth: CompleteFileUploadAuth,
    idempotency_key: str = Header(alias="Idempotency-Key"),
) -> JSONResponse:
    async with transaction(workspace_id=auth.workspace_id, isolation="READ COMMITTED") as connection:
        body = await lifecycle.complete_upload(
            connection,
            auth=auth,
            file_public_id=file_id,
            etag=payload.etag,
            idempotency_key=idempotency_key,
        )
    return JSONResponse(body.model_dump(mode="json"), status_code=200)


@app.get("/files/{file_id}", tags=["files"])
async def get_file(
    file_id: str,
    auth: GetFileAuth,
) -> JSONResponse:
    async with transaction(workspace_id=auth.workspace_id, isolation="READ COMMITTED") as connection:
        body = await lifecycle.get_file(connection, auth=auth, file_public_id=file_id)
    return JSONResponse(body.model_dump(mode="json"), status_code=200)


@app.delete("/files/{file_id}", tags=["files"])
async def delete_file(
    file_id: str,
    auth: DeleteFileAuth,
    idempotency_key: str = Header(alias="Idempotency-Key"),
) -> JSONResponse:
    async with transaction(workspace_id=auth.workspace_id, isolation="READ COMMITTED") as connection:
        body = await lifecycle.delete_file(
            connection,
            auth=auth,
            file_public_id=file_id,
            idempotency_key=idempotency_key,
        )
    return JSONResponse(body.model_dump(mode="json"), status_code=202)
