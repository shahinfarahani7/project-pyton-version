from __future__ import annotations

from collections import Counter
from typing import Annotated, Any

from fastapi import Depends, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from edgemint.building_blocks.app import create_service_app
from edgemint.building_blocks.database import transaction
from edgemint.building_blocks.settings import get_settings
from edgemint.dev.fibonai_credits import credits_by_task, sum_credited_points
from edgemint.operations.auth import (
    CSRF_HEADER,
    OPERATOR_SESSION_TTL,
    OperatorSession,
    cookie_name,
    dev_login_enabled,
    issue_operator_session,
    require_operator,
)
from edgemint.operations.errors import OperationsServiceError, operations_error
from edgemint.operations.portal_admin import admin_roles, portal_email_for_principal
from edgemint.operations.service import OperationsService
from edgemint.operations.task_monitor import (
    TaskMonitorUnavailable,
    TaskNotFound,
    build_task_monitor,
    cancel_monitored_task,
    device_ids_in,
    fetch_dev_sources,
    load_devices,
    with_tokens_given,
)
from edgemint.operations.worker_device_overview import (
    list_worker_device_overview,
    worker_has_current_app,
)
from edgemint.security.tokens import BrowserSessionStore
from edgemint.workers.app_release import WorkerAppReleaseError, resolve_worker_app_release

app = create_service_app("operations")
operations_service = OperationsService()

Operator = Annotated[OperatorSession, Depends(require_operator)]


class DevLoginRequest(BaseModel):
    operatorId: str = "op_dev_1"
    role: str = "operator.approver"


class OperatorActionRequest(BaseModel):
    action: str
    resourceId: str
    reasonCode: str
    ticketId: str
    expectedVersion: int | None = None


class BreakGlassRequest(BaseModel):
    reasonCode: str
    ticketId: str


class ExportRequest(BaseModel):
    view: str


@app.exception_handler(OperationsServiceError)
async def operations_service_error_handler(_: Request, exc: OperationsServiceError) -> JSONResponse:
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


def _session_body(session: OperatorSession) -> dict[str, object]:
    return {
        "operatorId": session.operator_id,
        "role": session.role,
        "mfaVerified": session.mfa_verified,
        "permissions": sorted(session.permissions),
        "expiresAt": session.expires_at.isoformat(),
    }


def _session_response(session: OperatorSession, status_code: int = 200) -> JSONResponse:
    response = JSONResponse(_session_body(session), status_code=status_code)
    response.headers[CSRF_HEADER] = session.csrf_token
    return response


@app.post("/internal/operations/session:dev-login", tags=["operations-auth"])
async def dev_login(payload: DevLoginRequest) -> JSONResponse:
    settings = get_settings()
    if not dev_login_enabled(settings):
        raise operations_error("DEV_LOGIN_DISABLED")
    token, session = issue_operator_session(
        operator_id=payload.operatorId,
        role=payload.role,
        mfa_verified=True,
        settings=settings,
    )
    return _signed_in_response(token, session)


@app.post("/internal/operations/session:portal", tags=["operations-auth"])
async def portal_login(request: Request) -> JSONResponse:
    settings = get_settings()
    if not dev_login_enabled(settings):
        raise operations_error("DEV_LOGIN_DISABLED")
    portal_token = BrowserSessionStore.read_session_cookie(
        request.cookies, environment=settings.environment
    )
    if not portal_token:
        raise operations_error("PORTAL_SESSION_REQUIRED")
    async with transaction(isolation="READ COMMITTED") as connection:
        record = await BrowserSessionStore().load_by_token(connection, session_token=portal_token)
        if record is None or not record.is_active():
            raise operations_error("PORTAL_SESSION_REQUIRED")
        email = await portal_email_for_principal(connection, record.principal_id)
    role = admin_roles(settings).get(email) if email else None
    if email is None or role is None:
        raise operations_error("AUTH_SCOPE_REQUIRED", detail="portal account is not an operations admin")
    token, session = issue_operator_session(
        operator_id=email,
        role=role,
        mfa_verified=True,
        settings=settings,
    )
    return _signed_in_response(token, session)


def _signed_in_response(token: str, session: OperatorSession) -> JSONResponse:
    settings = get_settings()
    response = _session_response(session, status_code=201)
    response.set_cookie(
        cookie_name(settings),
        token,
        max_age=int(OPERATOR_SESSION_TTL.total_seconds()),
        httponly=True,
        secure=settings.environment not in {"development", "test"},
        samesite="strict",
        path="/",
    )
    return response


@app.get("/internal/operations/session:sso", tags=["operations-auth"])
async def sso_login() -> JSONResponse:
    raise operations_error("SSO_NOT_CONFIGURED")


@app.get("/internal/operations/session", tags=["operations-auth"])
async def current_session(operator: Operator) -> JSONResponse:
    return _session_response(operator)


@app.post("/internal/operations/session:logout", tags=["operations-auth"])
async def logout(_: Operator) -> JSONResponse:
    response = JSONResponse({"status": "signed_out"}, status_code=200)
    response.delete_cookie(cookie_name(get_settings()), path="/")
    return response


@app.get("/internal/operations/views/{view_name}", tags=["operations"])
async def search_view(view_name: str, operator: Operator) -> JSONResponse:
    operator.require("operations.read")
    items = operations_service.search(view=view_name)
    return JSONResponse({"items": items, "page": {"limit": 50, "hasMore": False}}, status_code=200)


def _published_worker_app() -> dict[str, object] | None:
    try:
        release = resolve_worker_app_release(get_settings())
    except WorkerAppReleaseError:
        return None
    return {"versionName": release.version_name, "versionCode": release.version_code}


def _mark_updated_workers(
    items: list[dict[str, Any]],
    release: dict[str, object] | None,
) -> None:
    release_name = release.get("versionName") if release else None
    release_code = release.get("versionCode") if release else None
    for item in items:
        version = item.get("appVersion")
        code = item.get("appVersionCode")
        item["appUpdated"] = worker_has_current_app(
            app_version=version if isinstance(version, str) else None,
            app_version_code=code if type(code) is int else None,
            release_name=release_name if isinstance(release_name, str) else None,
            release_code=release_code if type(release_code) is int else None,
        )


@app.get("/internal/operations/worker-devices", tags=["operations"])
async def worker_devices(operator: Operator) -> JSONResponse:
    operator.require("operations.read")
    async with transaction(isolation="READ COMMITTED") as connection:
        items = await list_worker_device_overview(connection)
    release = _published_worker_app()
    _mark_updated_workers(items, release)
    return JSONResponse({"items": items, "release": release}, status_code=200)


async def _task_monitor() -> dict[str, object]:
    if not dev_login_enabled(get_settings()):
        raise operations_error("TASK_MONITOR_UNAVAILABLE", detail="only dev task state is wired")
    try:
        tasks, state = await fetch_dev_sources()
    except TaskMonitorUnavailable as exc:
        raise operations_error("UPSTREAM_UNAVAILABLE", detail=exc.source) from exc
    async with transaction(isolation="READ COMMITTED") as connection:
        devices = await load_devices(connection, device_ids_in(state))
        monitor = build_task_monitor(tasks, state, devices)
        credits = await credits_by_task(connection, [str(item["id"]) for item in monitor["items"]])
    return with_tokens_given(monitor, credits)


@app.get("/internal/operations/task-monitor", tags=["operations"])
async def task_monitor(operator: Operator) -> JSONResponse:
    operator.require("operations.read")
    return JSONResponse(await _task_monitor(), status_code=200)


@app.post("/internal/operations/tasks/{task_id}:cancel", tags=["operations"])
async def cancel_task(task_id: str, operator: Operator) -> JSONResponse:
    operator.require("operations.mutate.low")
    if not dev_login_enabled(get_settings()):
        raise operations_error("TASK_MONITOR_UNAVAILABLE", detail="only dev task state is wired")
    try:
        body = await cancel_monitored_task(task_id)
    except TaskNotFound:
        raise operations_error("TENANT_RESOURCE_NOT_FOUND") from None
    except TaskMonitorUnavailable as exc:
        raise operations_error("UPSTREAM_UNAVAILABLE", detail=exc.source) from exc
    return JSONResponse(body, status_code=200)


@app.get("/internal/operations/overview", tags=["operations"])
async def overview(operator: Operator) -> JSONResponse:
    operator.require("operations.read")
    async with transaction(isolation="READ COMMITTED") as connection:
        workers = await list_worker_device_overview(connection)
        issued_atomic = await sum_credited_points(connection)
    tasks: dict[str, object] | None
    task_error: str | None = None
    sold_atomic: int | None = None
    try:
        summary = (await _task_monitor())["summary"]
        tasks = summary  # type: ignore[assignment]
        raw_sold = summary.get("soldAtomic") if isinstance(summary, dict) else None
        if type(raw_sold) is int and raw_sold >= 0:
            sold_atomic = raw_sold
    except OperationsServiceError as exc:
        tasks = None
        task_error = exc.detail or exc.code
    return JSONResponse(
        {
            "workers": {
                "total": len(workers),
                "byPresence": dict(Counter(w["presence"] for w in workers)),
                "byActivity": dict(Counter(w["activity"] for w in workers)),
                "lowBattery": sum(
                    1
                    for w in workers
                    if w["presence"] == "online"
                    and w["battery"]["levelBps"] is not None
                    and w["battery"]["levelBps"] < 2_000
                    and not w["battery"]["charging"]
                ),
                "hotDevices": sum(
                    1
                    for w in workers
                    if w["presence"] == "online" and w["thermalState"] in {"serious", "critical"}
                ),
            },
            "tasks": tasks,
            "tasksError": task_error,
            "tokens": {"soldAtomic": sold_atomic, "issuedAtomic": issued_atomic},
        },
        status_code=200,
    )


@app.post("/internal/operations/actions:submit", tags=["operations"])
async def submit_action(payload: OperatorActionRequest, operator: Operator) -> JSONResponse:
    body = operations_service.submit_mutating_action(
        operator_id=operator.operator_id,
        role=operator.role,
        action=payload.action,
        resource_id=payload.resourceId,
        reason_code=payload.reasonCode,
        ticket_id=payload.ticketId,
        expected_version=payload.expectedVersion,
        permission="operations.mutate.low",
    )
    status = 202 if body.get("status") == "pending_approval" else 200
    return JSONResponse(body, status_code=status)


@app.post("/internal/operations/approvals/{approval_id}:approve", tags=["operations"])
async def approve_action(approval_id: str, operator: Operator) -> JSONResponse:
    body = operations_service.approve_action(
        approver_id=operator.operator_id,
        role=operator.role,
        approval_id=approval_id,
    )
    return JSONResponse(body, status_code=200)


@app.post("/internal/operations/break-glass:activate", tags=["operations"])
async def activate_break_glass(payload: BreakGlassRequest, operator: Operator) -> JSONResponse:
    session = operations_service.activate_break_glass(
        operator_id=operator.operator_id,
        role=operator.role,
        reason_code=payload.reasonCode,
        ticket_id=payload.ticketId,
    )
    return JSONResponse(
        {
            "sessionId": session.session_id,
            "expiresAt": session.expires_at.isoformat(),
            "paged": session.paged,
            "reviewRequired": not session.reviewed,
        },
        status_code=201,
    )


@app.post("/internal/operations/exports:audited", tags=["operations"])
async def export_audited(payload: ExportRequest, operator: Operator) -> JSONResponse:
    operator.require("operations.read")
    return JSONResponse(
        operations_service.export_audited_view(view=payload.view, operator_id=operator.operator_id),
        status_code=200,
    )


@app.get("/internal/operations/audit-log", tags=["operations"])
async def audit_log(operator: Operator) -> JSONResponse:
    operator.require("operations.read")
    return JSONResponse(
        {
            "items": [
                {
                    "auditId": item.audit_id,
                    "operatorId": item.operator_id,
                    "action": item.action,
                    "resourceId": item.resource_id,
                    "reasonCode": item.reason_code,
                    "ticketId": item.ticket_id,
                    "expectedVersion": item.expected_version,
                    "occurredAt": item.occurred_at,
                    "breakGlass": item.break_glass,
                }
                for item in operations_service.audit_log
            ]
        },
        status_code=200,
    )


@app.get("/internal/operations/session-recording/hooks", tags=["operations"])
async def session_recording_hooks(operator: Operator) -> JSONResponse:
    operator.require("operations.read")
    return JSONResponse({"items": operations_service.session_recording_hooks}, status_code=200)
