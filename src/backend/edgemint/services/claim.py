from __future__ import annotations

from typing import Any

from fastapi import Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from edgemint.building_blocks.app import create_service_app
from edgemint.claims.service import ClaimPayoutService
from edgemint.payments.errors import PaymentProviderError

app = create_service_app("claim")
claim_service = ClaimPayoutService()


class ClaimBatchRequest(BaseModel):
    batchId: str
    idempotencyKey: str
    claims: list[dict[str, Any]] = Field(min_length=1)


class RecoverPayoutRequest(BaseModel):
    payoutId: str
    idempotencyKey: str


@app.exception_handler(PaymentProviderError)
async def payment_provider_error_handler(_: Request, exc: PaymentProviderError) -> JSONResponse:
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


@app.post("/internal/claims/batches:submit", tags=["claim"])
async def submit_claim_batch(payload: ClaimBatchRequest) -> JSONResponse:
    body = claim_service.submit_claim_batch(
        batch_id=payload.batchId,
        claims=payload.claims,
        idempotency_key=payload.idempotencyKey,
    )
    return JSONResponse(body, status_code=202)


@app.post("/internal/claims/payouts:recover", tags=["claim"])
async def recover_failed_payout(payload: RecoverPayoutRequest) -> JSONResponse:
    body = claim_service.payments.recover_failed_payout(
        payout_id=payload.payoutId,
        idempotency_key=payload.idempotencyKey,
    )
    return JSONResponse(body, status_code=200)


@app.post("/internal/claims/eligibility:evaluate", tags=["claim"])
async def evaluate_eligibility(payload: dict[str, Any]) -> JSONResponse:
    from edgemint.claims.service import evaluate_claim_eligibility

    return JSONResponse(evaluate_claim_eligibility(payload), status_code=200)
