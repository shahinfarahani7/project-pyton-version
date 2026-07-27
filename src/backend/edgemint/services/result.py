from __future__ import annotations

from typing import Any

from fastapi import Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from edgemint.building_blocks.app import create_service_app
from edgemint.results.errors import ResultServiceError
from edgemint.results.intake import AssignmentBinding, ResultSubmission
from edgemint.security.tokens import hash_session_token
from edgemint.verification.service import VerificationService

app = create_service_app("result")
verification_service = VerificationService()


class CompleteAssignmentRequest(BaseModel):
    assignmentId: str
    attemptId: str
    workspaceId: str
    workerId: str
    workerDeviceId: str
    taskId: str
    taskType: str = "document.ocr"
    verificationLevel: str = "standard"
    leaseToken: str
    fenceToken: int = Field(ge=1)
    resultSha256: str = Field(min_length=64, max_length=64)
    outputArtifactId: str
    signature: str
    metrics: dict[str, Any] = Field(default_factory=dict)
    outputInline: str | None = None
    outputFileId: str | None = None
    modelDigest: str | None = None
    inputDigest: str | None = None
    isGoldenTask: bool = False


@app.exception_handler(ResultServiceError)
async def result_service_error_handler(_: Request, exc: ResultServiceError) -> JSONResponse:
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


@app.get("/result/policy", tags=["result"])
async def get_result_policy() -> JSONResponse:
    explanation = verification_service.explain_decision(task_type="document.ocr")
    return JSONResponse(explanation, status_code=200)


@app.post("/internal/result/intake", tags=["result"])
async def intake_result(payload: CompleteAssignmentRequest) -> JSONResponse:
    submission = ResultSubmission(
        assignment_id=payload.assignmentId,
        attempt_id=payload.attemptId,
        lease_token=payload.leaseToken,
        fence_token=payload.fenceToken,
        result_sha256=payload.resultSha256,
        output_artifact_id=payload.outputArtifactId,
        signature=payload.signature,
        metrics=payload.metrics,
        output_inline=payload.outputInline,
        output_file_id=payload.outputFileId,
        submitted_model_digest=payload.modelDigest,
        submitted_input_digest=payload.inputDigest,
    )
    binding = AssignmentBinding(
        assignment_id=payload.assignmentId,
        attempt_id=payload.attemptId,
        workspace_id=payload.workspaceId,
        worker_id=payload.workerId,
        worker_device_id=payload.workerDeviceId,
        task_type=payload.taskType,
        verification_level=payload.verificationLevel,
        lease_token_hash=hash_session_token(payload.leaseToken),
        fence_token=payload.fenceToken,
        model_digest=payload.modelDigest or "a" * 64,
        input_digest=payload.inputDigest or "b" * 64,
        is_golden_task=payload.isGoldenTask,
    )
    body = verification_service.intake_and_verify(
        submission,
        binding,
        task_id=payload.taskId,
        inline_output=payload.outputInline,
    )
    return JSONResponse(body, status_code=202)
