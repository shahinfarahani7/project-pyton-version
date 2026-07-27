from __future__ import annotations

from fastapi import Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from edgemint.building_blocks.app import create_service_app
from edgemint.operations.errors import OperationsServiceError
from edgemint.operations.service import OperationsService

app = create_service_app("operations")
operations_service = OperationsService()


class OperatorActionRequest(BaseModel):
    operatorId: str
    role: str
    action: str
    resourceId: str
    reasonCode: str
    ticketId: str
    permission: str
    expectedVersion: int | None = None


class ApprovalRequest(BaseModel):
    approverId: str
    role: str = "operator.approver"


class BreakGlassRequest(BaseModel):
    operatorId: str
    role: str = "operator.break_glass"
    reasonCode: str
    ticketId: str


class ExportRequest(BaseModel):
    operatorId: str
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


@app.get("/internal/operations/views/{view_name}", tags=["operations"])
async def search_view(view_name: str) -> JSONResponse:
    items = operations_service.search(view=view_name)
    return JSONResponse({"items": items, "page": {"limit": 50, "hasMore": False}}, status_code=200)


@app.post("/internal/operations/actions:submit", tags=["operations"])
async def submit_action(payload: OperatorActionRequest) -> JSONResponse:
    body = operations_service.submit_mutating_action(
        operator_id=payload.operatorId,
        role=payload.role,
        action=payload.action,
        resource_id=payload.resourceId,
        reason_code=payload.reasonCode,
        ticket_id=payload.ticketId,
        expected_version=payload.expectedVersion,
        permission=payload.permission,
    )
    status = 202 if body.get("status") == "pending_approval" else 200
    return JSONResponse(body, status_code=status)


@app.post("/internal/operations/approvals/{approval_id}:approve", tags=["operations"])
async def approve_action(approval_id: str, payload: ApprovalRequest) -> JSONResponse:
    body = operations_service.approve_action(
        approver_id=payload.approverId,
        role=payload.role,
        approval_id=approval_id,
    )
    return JSONResponse(body, status_code=200)


@app.post("/internal/operations/break-glass:activate", tags=["operations"])
async def activate_break_glass(payload: BreakGlassRequest) -> JSONResponse:
    session = operations_service.activate_break_glass(
        operator_id=payload.operatorId,
        role=payload.role,
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
async def export_audited(payload: ExportRequest) -> JSONResponse:
    return JSONResponse(
        operations_service.export_audited_view(view=payload.view, operator_id=payload.operatorId),
        status_code=200,
    )


@app.get("/internal/operations/audit-log", tags=["operations"])
async def audit_log() -> JSONResponse:
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
async def session_recording_hooks() -> JSONResponse:
    return JSONResponse({"items": operations_service.session_recording_hooks}, status_code=200)
