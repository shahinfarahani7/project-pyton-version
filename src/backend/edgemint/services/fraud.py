from __future__ import annotations

from typing import Any

from fastapi import Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from edgemint.building_blocks.app import create_service_app
from edgemint.fraud.errors import FraudServiceError
from edgemint.fraud.service import FraudService

app = create_service_app("fraud")
fraud_service = FraudService()


class EvaluateSignalsRequest(BaseModel):
    signals: dict[str, bool]
    deviceLinks: list[dict[str, str]] = Field(default_factory=list)
    velocityEvents: list[dict[str, Any]] = Field(default_factory=list)
    goldenTrap: dict[str, str] | None = None


class OpenCaseRequest(BaseModel):
    subjectId: str
    operatorId: str
    reason: str
    signals: dict[str, bool]
    evidence: dict[str, Any] = Field(default_factory=dict)


class ApplyActionsRequest(BaseModel):
    subjectId: str
    operatorId: str
    reason: str
    evaluation: dict[str, Any]


class AppealRequest(BaseModel):
    submitterId: str
    evidence: dict[str, Any]


class ReverseActionRequest(BaseModel):
    actionId: str
    operatorId: str
    reason: str


class DsarRequest(BaseModel):
    subjectId: str
    requestType: str


class PrivacyDeleteRequest(BaseModel):
    retainedRecords: list[dict[str, Any]] = Field(default_factory=list)


class MinimizeProfileRequest(BaseModel):
    payload: dict[str, Any]


@app.exception_handler(FraudServiceError)
async def fraud_service_error_handler(_: Request, exc: FraudServiceError) -> JSONResponse:
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


@app.post("/internal/fraud/signals:evaluate", tags=["fraud"])
async def evaluate_signals(payload: EvaluateSignalsRequest) -> JSONResponse:
    body = fraud_service.evaluate_with_context(
        signals=payload.signals,
        device_links=payload.deviceLinks or None,
        velocity_events=payload.velocityEvents or None,
        golden_trap=payload.goldenTrap,
    )
    return JSONResponse(body, status_code=200)


@app.post("/internal/fraud/cases:open", tags=["fraud"])
async def open_case(payload: OpenCaseRequest) -> JSONResponse:
    evaluation = fraud_service.evaluate_signals(payload.signals)
    case = fraud_service.open_case_from_evaluation(
        subject_id=payload.subjectId,
        evaluation=evaluation,
        operator_id=payload.operatorId,
        reason=payload.reason,
        evidence=payload.evidence,
    )
    return JSONResponse(case, status_code=201)


@app.post("/internal/fraud/cases/{case_id}/actions:apply", tags=["fraud"])
async def apply_actions(case_id: str, payload: ApplyActionsRequest) -> JSONResponse:
    applied = fraud_service.apply_policy_actions(
        case_id=case_id,
        evaluation=payload.evaluation,
        subject_id=payload.subjectId,
        operator_id=payload.operatorId,
        reason=payload.reason,
    )
    return JSONResponse({"caseId": case_id, "applied": applied}, status_code=200)


@app.post("/internal/fraud/cases/{case_id}/appeals:submit", tags=["fraud"])
async def submit_appeal(case_id: str, payload: AppealRequest) -> JSONResponse:
    appeal = fraud_service.workflow.submit_appeal(
        case_id=case_id,
        submitter_id=payload.submitterId,
        evidence=payload.evidence,
    )
    return JSONResponse(appeal, status_code=201)


@app.post("/internal/fraud/cases/{case_id}/actions:reverse", tags=["fraud"])
async def reverse_action(case_id: str, payload: ReverseActionRequest) -> JSONResponse:
    reversal = fraud_service.workflow.reverse_action(
        case_id=case_id,
        action_id=payload.actionId,
        operator_id=payload.operatorId,
        reason=payload.reason,
    )
    return JSONResponse(
        {
            "actionId": reversal.action_id,
            "actionType": reversal.action_type,
            "status": reversal.status,
            "version": reversal.version,
        },
        status_code=200,
    )


@app.get("/internal/fraud/incidents/{incident_type}/playbook", tags=["fraud"])
async def incident_playbook(incident_type: str) -> JSONResponse:
    steps = fraud_service.incident_playbook(incident_type)
    return JSONResponse({"incidentType": incident_type, "steps": steps}, status_code=200)


@app.post("/internal/fraud/privacy/dsar:submit", tags=["fraud"])
async def submit_dsar(payload: DsarRequest) -> JSONResponse:
    request = fraud_service.submit_dsar(subject_id=payload.subjectId, request_type=payload.requestType)
    return JSONResponse(request, status_code=201)


@app.post("/internal/fraud/privacy/subjects/{subject_id}:delete", tags=["fraud"])
async def delete_subject(subject_id: str, payload: PrivacyDeleteRequest) -> JSONResponse:
    result = fraud_service.delete_subject_data(
        subject_id=subject_id,
        retained_records=payload.retainedRecords,
    )
    return JSONResponse(result, status_code=200)


@app.post("/internal/fraud/privacy/subjects/{subject_id}:minimize", tags=["fraud"])
async def minimize_profile(subject_id: str, payload: MinimizeProfileRequest) -> JSONResponse:
    profile = fraud_service.minimize_profile(subject_id=subject_id, payload=payload.payload)
    return JSONResponse(profile, status_code=200)
