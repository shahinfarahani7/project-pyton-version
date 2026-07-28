from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from edgemint.building_blocks.database import transaction
from edgemint.building_blocks.settings import get_settings
from edgemint.dev import fixtures
from edgemint.security.problems import raise_auth_error
from edgemint.security.tokens import BrowserSessionRecord, BrowserSessionStore

router = APIRouter()
session_store = BrowserSessionStore()


class DevCreateTaskRequest(BaseModel):
    taskType: str = Field(min_length=1, max_length=128)


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


@router.get("/v1/workspaces/{workspace_id}/tasks")
async def list_tasks(
    workspace_id: UUID,
    session: BrowserSessionRecord = Depends(require_dev_portal_session),
) -> dict:
    _ensure_workspace_access(session, workspace_id)
    return fixtures.dev_tasks(workspace_id)


@router.post("/v1/workspaces/{workspace_id}/tasks", status_code=201)
async def create_task(
    workspace_id: UUID,
    payload: DevCreateTaskRequest,
    session: BrowserSessionRecord = Depends(require_dev_portal_session),
) -> dict:
    _ensure_workspace_access(session, workspace_id)
    return fixtures.create_dev_task(workspace_id, task_type=payload.taskType)


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
    return task


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
