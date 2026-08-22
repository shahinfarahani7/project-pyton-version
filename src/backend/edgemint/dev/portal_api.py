from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, Form, HTTPException, Request, UploadFile
from pydantic import BaseModel, Field

from edgemint.building_blocks.database import transaction
from edgemint.building_blocks.settings import get_settings
from edgemint.dev import fixtures
from edgemint.dev import task_type_catalog
from edgemint.security.problems import raise_auth_error
from edgemint.security.tokens import BrowserSessionRecord, BrowserSessionStore

router = APIRouter()
session_store = BrowserSessionStore()


class DevCreateTaskRequest(BaseModel):
    taskType: str = Field(min_length=1, max_length=128)
    inputText: str | None = Field(default=None, max_length=32_000)
    instructions: str | None = Field(default=None, max_length=8_000)


async def _read_uploaded_file(upload: object | None) -> tuple[str | None, str | None, bytes | None]:
    """Accept Starlette or FastAPI UploadFile (isinstance checks differ across versions)."""
    if upload is None or not hasattr(upload, "read"):
        return None, None, None
    file_name = getattr(upload, "filename", None) or getattr(upload, "name", None)
    if not file_name:
        return None, None, None
    file_bytes = await upload.read()  # type: ignore[union-attr]
    file_mime = getattr(upload, "content_type", None)
    return str(file_name), file_mime, file_bytes


async def _create_task_from_form(
    workspace_id: UUID,
    *,
    task_type: str,
    input_text: str | None,
    instructions: str | None,
    file_name: str | None,
    file_mime: str | None,
    file_bytes: bytes | None,
) -> dict:
    if not task_type.strip():
        raise HTTPException(422, "TASK_TYPE_REQUIRED")
    try:
        task_type_catalog.validate_task_submission(
            task_type=task_type,
            input_text=input_text,
            instructions=instructions,
            file_name=file_name,
            file_mime=file_mime,
            file_bytes=file_bytes,
        )
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc
    task = fixtures.create_dev_task(
        workspace_id,
        task_type=task_type.strip(),
        input_text=input_text,
        instructions=instructions,
        file_name=file_name,
        file_mime=file_mime,
        file_bytes=file_bytes,
    )
    return task_type_catalog.enrich_task_row(task)


async def require_dev_portal_session(request: Request) -> BrowserSessionRecord:
    settings = get_settings()
    if settings.environment not in {"development", "test"}:
        raise HTTPException(503, "DEV_PORTAL_API_DISABLED")

    session_token = BrowserSessionStore.read_session_cookie(
        request.cookies, environment=get_settings().environment
    )
    if not session_token:
        raise_auth_error("AUTH_INVALID_CREDENTIAL")

    async with transaction() as connection:
        record = await session_store.load_by_token(connection, session_token=session_token)
        if record is None or not record.is_active():
            raise_auth_error("AUTH_SESSION_REVOKED")
        return record


def _ensure_workspace_access(session: BrowserSessionRecord, workspace_id: UUID) -> None:
    if not fixtures.is_dev_principal(session.principal_id):
        raise HTTPException(403, "WORKSPACE_ACCESS_DENIED")
    if workspace_id not in fixtures.DEV_WORKSPACE_IDS:
        raise HTTPException(404, "WORKSPACE_NOT_FOUND")
    if session.workspace_id != workspace_id:
        raise HTTPException(403, "WORKSPACE_SESSION_MISMATCH")


@router.get("/v1/me")
async def current_principal(session: BrowserSessionRecord = Depends(require_dev_portal_session)) -> dict:
    if not fixtures.is_dev_principal(session.principal_id):
        return {
            "id": str(session.principal_id),
            "displayName": "Portal User",
            "email": None,
            "subject": str(session.principal_id),
        }
    return fixtures.dev_principal()


@router.get("/v1/workspaces")
async def list_workspaces(session: BrowserSessionRecord = Depends(require_dev_portal_session)) -> dict:
    if not fixtures.is_dev_principal(session.principal_id):
        return {"items": [], "page": fixtures.PAGE}
    return {"items": fixtures.dev_workspaces(), "page": fixtures.PAGE}


@router.get("/v1/task-types")
async def list_task_types(
    q: str | None = None,
    locale: str = "en",
    session: BrowserSessionRecord = Depends(require_dev_portal_session),
) -> dict:
    _ = session
    normalized_locale = "fa" if locale == "fa" else "en"
    return task_type_catalog.list_catalog(query=q, locale=normalized_locale)


@router.get("/v1/workspaces/{workspace_id}/tasks")
async def list_tasks(
    workspace_id: UUID,
    session: BrowserSessionRecord = Depends(require_dev_portal_session),
) -> dict:
    _ensure_workspace_access(session, workspace_id)
    return task_type_catalog.enrich_task_list(fixtures.dev_tasks(workspace_id))


@router.post("/v1/workspaces/{workspace_id}/tasks", status_code=201)
async def create_task(
    request: Request,
    workspace_id: UUID,
    session: BrowserSessionRecord = Depends(require_dev_portal_session),
) -> dict:
    _ensure_workspace_access(session, workspace_id)
    content_type = request.headers.get("content-type", "")
    try:
        if "multipart/form-data" in content_type:
            form = await request.form()
            task_type = str(form.get("taskType", "")).strip()
            raw_text = form.get("inputText")
            input_text = raw_text.strip() if isinstance(raw_text, str) and raw_text.strip() else None
            raw_instructions = form.get("instructions")
            instructions = (
                raw_instructions.strip()
                if isinstance(raw_instructions, str) and raw_instructions.strip()
                else None
            )
            file_name, file_mime, file_bytes = await _read_uploaded_file(form.get("inputFile"))
            return await _create_task_from_form(
                workspace_id,
                task_type=task_type,
                input_text=input_text,
                instructions=instructions,
                file_name=file_name,
                file_mime=file_mime,
                file_bytes=file_bytes,
            )
        payload = DevCreateTaskRequest.model_validate(await request.json())
        return await _create_task_from_form(
            workspace_id,
            task_type=payload.taskType,
            input_text=payload.inputText,
            instructions=payload.instructions,
            file_name=None,
            file_mime=None,
            file_bytes=None,
        )
    except ValueError as exc:
        if str(exc) == "INPUT_FILE_TOO_LARGE":
            raise HTTPException(413, "INPUT_FILE_TOO_LARGE") from exc
        if str(exc) in {
            "UNSUPPORTED_TASK_TYPE",
            "INPUT_TEXT_REQUIRED",
            "INPUT_IMAGE_REQUIRED",
            "INPUT_FILE_OR_TEXT_REQUIRED",
            "TASK_TYPE_REQUIRED",
        }:
            raise HTTPException(422, str(exc)) from exc
        raise


@router.post("/v1/workspaces/{workspace_id}/tasks/upload", status_code=201)
async def create_task_multipart(
    workspace_id: UUID,
    task_type: str = Form(..., alias="taskType"),
    session: BrowserSessionRecord = Depends(require_dev_portal_session),
    input_text: str | None = Form(default=None, alias="inputText"),
    instructions: str | None = Form(default=None, alias="instructions"),
    input_file: UploadFile | None = Form(default=None, alias="inputFile"),
) -> dict:
    """Explicit multipart route — reliable file upload from browser FormData."""
    _ensure_workspace_access(session, workspace_id)
    try:
        file_name, file_mime, file_bytes = await _read_uploaded_file(input_file)
        normalized_text = input_text.strip() if input_text and input_text.strip() else None
        normalized_instructions = instructions.strip() if instructions and instructions.strip() else None
        return await _create_task_from_form(
            workspace_id,
            task_type=task_type,
            input_text=normalized_text,
            instructions=normalized_instructions,
            file_name=file_name,
            file_mime=file_mime,
            file_bytes=file_bytes,
        )
    except ValueError as exc:
        if str(exc) == "INPUT_FILE_TOO_LARGE":
            raise HTTPException(413, "INPUT_FILE_TOO_LARGE") from exc
        raise


@router.get("/v1/workspaces/{workspace_id}/tasks/{task_id}")
async def get_task(
    workspace_id: UUID,
    task_id: str,
    session: BrowserSessionRecord = Depends(require_dev_portal_session),
) -> dict:
    _ensure_workspace_access(session, workspace_id)
    task = fixtures.dev_task(workspace_id, task_id)
    if task is None:
        raise HTTPException(404, "TASK_NOT_FOUND")
    return task_type_catalog.enrich_task_row(task)


@router.get("/v1/workspaces/{workspace_id}/tasks/{task_id}/result-file")
async def get_task_result_file(
    workspace_id: UUID,
    task_id: str,
    session: BrowserSessionRecord = Depends(require_dev_portal_session),
):
    from edgemint.dev import worker_task_inputs

    _ensure_workspace_access(session, workspace_id)
    task = fixtures.dev_task(workspace_id, task_id)
    if task is None:
        raise HTTPException(404, "TASK_NOT_FOUND")
    blob = worker_task_inputs.result_content(task_id)
    if blob is None:
        raise HTTPException(404, "TASK_RESULT_NOT_FOUND")
    return worker_task_inputs.content_response(blob)


@router.get("/v1/webhook-endpoints")
async def list_webhooks(session: BrowserSessionRecord = Depends(require_dev_portal_session)) -> dict:
    return fixtures.dev_webhooks(session.workspace_id)


@router.get("/v1/api-keys")
async def list_api_keys(session: BrowserSessionRecord = Depends(require_dev_portal_session)) -> dict:
    return fixtures.dev_api_keys(session.workspace_id)


@router.get("/v1/workspaces/{workspace_id}/usage")
async def workspace_usage(
    workspace_id: UUID,
    session: BrowserSessionRecord = Depends(require_dev_portal_session),
) -> dict:
    _ensure_workspace_access(session, workspace_id)
    return fixtures.dev_usage(workspace_id)


@router.get("/v1/workspaces/{workspace_id}/credit-balance")
async def workspace_balance(
    workspace_id: UUID,
    session: BrowserSessionRecord = Depends(require_dev_portal_session),
) -> dict:
    _ensure_workspace_access(session, workspace_id)
    return fixtures.dev_credit_balance(workspace_id)


@router.get("/v1/workspaces/{workspace_id}/invoices")
async def workspace_invoices(
    workspace_id: UUID,
    session: BrowserSessionRecord = Depends(require_dev_portal_session),
) -> dict:
    _ensure_workspace_access(session, workspace_id)
    return fixtures.dev_invoices(workspace_id)


@router.get("/v1/workspaces/{workspace_id}/disputes")
async def workspace_disputes(
    workspace_id: UUID,
    session: BrowserSessionRecord = Depends(require_dev_portal_session),
) -> dict:
    _ensure_workspace_access(session, workspace_id)
    return fixtures.dev_disputes(workspace_id)
