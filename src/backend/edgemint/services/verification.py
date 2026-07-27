from __future__ import annotations

from fastapi import Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from edgemint.building_blocks.app import create_service_app
from edgemint.verification.consensus import ConsensusVote
from edgemint.verification.errors import VerificationServiceError
from edgemint.verification.service import VerificationService

app = create_service_app("verification")
verification_service = VerificationService()


class ConsensusVotePayload(BaseModel):
    workerId: str
    workerDeviceId: str
    resultSha256: str = Field(min_length=64, max_length=64)
    similarityMilli: int = Field(ge=0, le=1000)
    decision: str


class RunConsensusRequest(BaseModel):
    taskId: str
    taskType: str = "document.ocr"
    verificationLevel: str = "consensus"
    votes: list[ConsensusVotePayload]


@app.exception_handler(VerificationServiceError)
async def verification_service_error_handler(_: Request, exc: VerificationServiceError) -> JSONResponse:
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


@app.get("/verification/policy", tags=["verification"])
async def get_verification_policy(taskType: str = "document.ocr") -> JSONResponse:
    return JSONResponse(verification_service.explain_decision(task_type=taskType), status_code=200)


@app.post("/internal/verification/consensus", tags=["verification"])
async def run_consensus(payload: RunConsensusRequest) -> JSONResponse:
    votes = [
        ConsensusVote(
            worker_id=item.workerId,
            worker_device_id=item.workerDeviceId,
            result_sha256=item.resultSha256,
            similarity_milli=item.similarityMilli,
            decision=item.decision,
        )
        for item in payload.votes
    ]
    body = verification_service.run_consensus(
        task_type=payload.taskType,
        verification_level=payload.verificationLevel,
        votes=votes,
    )
    return JSONResponse(body, status_code=202)


@app.get("/internal/verification/human-review", tags=["verification"])
async def list_human_review_queue() -> JSONResponse:
    return JSONResponse({"items": verification_service.human_review_queue.as_dict()}, status_code=200)
