from __future__ import annotations

import asyncio
import json
from typing import Any
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from edgemint.building_blocks.database import transaction
from edgemint.building_blocks.settings import get_settings
from edgemint.dev import fixtures
from edgemint.dev import task_events
from edgemint.dev import task_type_catalog
from edgemint.security.problems import raise_auth_error
from edgemint.security.tokens import BrowserSessionRecord, BrowserSessionStore

try:
    from edgemint.tasks.catalog_closure import validate_queue_admission
    from edgemint.tasks.errors import TaskServiceError
except ModuleNotFoundError:
    validate_queue_admission = None  # type: ignore[misc, assignment]

    class TaskServiceError(Exception):  # noqa: N818
        status = 422
        code = "TASK_CREATE_FAILED"

try:
    from edgemint.results.text_summarize_constraints import (
        SummarizeConstraintsError,
        parse_summarize_constraints,
    )
except ModuleNotFoundError:

    class SummarizeConstraintsError(ValueError):
        pass

    def parse_summarize_constraints(raw: dict[str, Any]) -> Any:  # noqa: ARG001
        return None

router = APIRouter()
session_store = BrowserSessionStore()

_MAX_INPUT_TEXT_CHARS = 32_000
_MAX_INSTRUCTIONS_CHARS = 8_000


def _bounded_form_text(
    value: object | None,
    *,
    max_length: int,
    error_code: str,
) -> str | None:
    if value is None:
        return None
    text = str(value)
    if len(text) > max_length:
        raise ValueError(error_code)
    return text


class DevAddWalletRequest(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    amountMicroEur: int = Field(gt=0, le=1_000_000_000_000)


class DevCreateTaskRequest(BaseModel):
    taskType: str = Field(min_length=1, max_length=128)
    inputText: str | None = Field(default=None, max_length=32_000)
    instructions: str | None = Field(default=None, max_length=8_000)
    summarizeOptions: dict[str, Any] | None = None


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


def _parse_summarize_options(raw: object | None) -> dict[str, Any] | None:
    if raw is None:
        return None
    if isinstance(raw, str):
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise HTTPException(422, "SUMMARIZE_OPTIONS_INVALID_JSON") from exc
        if not isinstance(parsed, dict):
            raise HTTPException(422, "SUMMARIZE_OPTIONS_MUST_BE_OBJECT")
        raw = parsed
    if not isinstance(raw, dict):
        raise HTTPException(422, "SUMMARIZE_OPTIONS_MUST_BE_OBJECT")
    try:
        constraints = parse_summarize_constraints(raw)
    except SummarizeConstraintsError as exc:
        raise HTTPException(422, str(exc)) from exc
    if constraints is None:
        return None
    return raw


async def _create_task_from_form(
    workspace_id: UUID,
    *,
    task_type: str,
    input_text: str | None,
    instructions: str | None,
    file_name: str | None,
    file_mime: str | None,
    file_bytes: bytes | None,
    summarize_options: dict[str, Any] | None = None,
) -> dict:
    settings = get_settings()
    if settings.environment in {"development", "test"}:
        task_type_catalog.reload_catalog_cache()
    normalized_type = task_type.strip()
    if not normalized_type:
        raise HTTPException(422, "TASK_TYPE_REQUIRED")
    if task_type_catalog.get_task_type(normalized_type) is None:
        raise HTTPException(422, "UNSUPPORTED_TASK_TYPE")
    try:
        try:
            if validate_queue_admission is not None:
                validate_queue_admission(catalog_code=normalized_type, mode="baseline")
        except ModuleNotFoundError:
            pass
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
    except TaskServiceError as exc:
        raise HTTPException(exc.status, exc.code) from exc
    task = fixtures.create_dev_task(
        workspace_id,
        task_type=task_type.strip(),
        input_text=input_text,
        instructions=instructions,
        file_name=file_name,
        file_mime=file_mime,
        file_bytes=file_bytes,
        summarize_options=summarize_options,
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


@router.get("/v1/workspaces/{workspace_id}/tasks/events")
async def stream_task_events(
    workspace_id: UUID,
    session: BrowserSessionRecord = Depends(require_dev_portal_session),
) -> StreamingResponse:
    """Push task create/update events to the portal (SSE — no polling)."""
    _ensure_workspace_access(session, workspace_id)

    async def event_stream():
        queue = await task_events.subscribe(workspace_id)
        try:
            yield "event: ready\ndata: {}\n\n"
            while True:
                try:
                    payload = await asyncio.wait_for(queue.get(), timeout=30.0)
                except asyncio.TimeoutError:
                    yield ": heartbeat\n\n"
                    continue
                yield f"event: task\ndata: {payload}\n\n"
        finally:
            await task_events.unsubscribe(workspace_id, queue)

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


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
            task_type = str(form.get("taskType") or "").strip()
            input_text = _bounded_form_text(
                form.get("inputText"),
                max_length=_MAX_INPUT_TEXT_CHARS,
                error_code="INPUT_TEXT_TOO_LONG",
            )
            instructions = _bounded_form_text(
                form.get("instructions"),
                max_length=_MAX_INSTRUCTIONS_CHARS,
                error_code="INSTRUCTIONS_TOO_LONG",
            )
            upload = form.get("inputFile")
            file_name, file_mime, file_bytes = await _read_uploaded_file(upload)
            return await _create_task_from_form(
                workspace_id,
                task_type=task_type,
                input_text=input_text,
                instructions=instructions,
                file_name=file_name,
                file_mime=file_mime,
                file_bytes=file_bytes,
                summarize_options=_parse_summarize_options(form.get("summarizeOptions")),
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
            summarize_options=payload.summarizeOptions,
        )
    except ValueError as exc:
        if str(exc) == "INPUT_FILE_TOO_LARGE":
            raise HTTPException(413, "INPUT_FILE_TOO_LARGE") from exc
        if str(exc) in {
            "UNSUPPORTED_TASK_TYPE",
            "INPUT_TEXT_REQUIRED",
            "INPUT_TEXT_TOO_LONG",
            "INSTRUCTIONS_TOO_LONG",
            "INPUT_IMAGE_REQUIRED",
            "INPUT_FILE_OR_TEXT_REQUIRED",
            "TASK_TYPE_REQUIRED",
            "FLEX_INPUT_MUST_BE_JSON_OBJECT",
        }:
            raise HTTPException(422, str(exc)) from exc
        raise HTTPException(500, "TASK_CREATE_FAILED") from exc


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


@router.post("/v1/workspaces/{workspace_id}/tasks/{task_id}:cancel")
async def cancel_task(
    workspace_id: UUID,
    task_id: str,
    session: BrowserSessionRecord = Depends(require_dev_portal_session),
) -> dict:
    _ensure_workspace_access(session, workspace_id)
    task = fixtures.cancel_dev_task(workspace_id, task_id)
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


@router.get("/v1/workspaces/{workspace_id}/wallets")
async def list_wallets(
    workspace_id: UUID,
    session: BrowserSessionRecord = Depends(require_dev_portal_session),
) -> dict:
    _ensure_workspace_access(session, workspace_id)
    return fixtures.dev_wallets(workspace_id)


@router.post("/v1/workspaces/{workspace_id}/wallets")
async def create_wallet(
    workspace_id: UUID,
    body: DevAddWalletRequest,
    session: BrowserSessionRecord = Depends(require_dev_portal_session),
) -> dict:
    _ensure_workspace_access(session, workspace_id)
    try:
        return fixtures.add_dev_wallet(
            workspace_id,
            name=body.name,
            amount_micro_eur=body.amountMicroEur,
        )
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc


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
