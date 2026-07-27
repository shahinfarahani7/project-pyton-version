from __future__ import annotations

from typing import Any

from fastapi import Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from edgemint.billing.errors import FinanceServiceError
from edgemint.billing.service import FinanceService
from edgemint.building_blocks.app import create_service_app
from edgemint.payments.adapters.stripe.sandbox import StripeSandboxAdapter
from edgemint.payments.errors import PaymentProviderError
from edgemint.payments.service import PaymentProviderService

app = create_service_app("billing")
finance_service = FinanceService()
payment_provider = PaymentProviderService()


class CaptureReservationRequest(BaseModel):
    taskId: str
    quoteId: str
    amountMicroEur: int = Field(ge=0)
    availableMicroEur: int = Field(ge=0)


class FinalizePaidTaskRequest(BaseModel):
    idempotencyKey: str
    taskId: str
    taskRevisionId: str
    resultId: str
    verificationId: str
    priceInput: dict[str, Any]
    rewardInput: dict[str, Any]
    refundMicros: int = 0


@app.exception_handler(FinanceServiceError)
async def finance_service_error_handler(_: Request, exc: FinanceServiceError) -> JSONResponse:
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


@app.post("/internal/billing/reservations:capture", tags=["billing"])
async def capture_reservation(payload: CaptureReservationRequest) -> JSONResponse:
    reservation = finance_service.capture_reservation(
        task_id=payload.taskId,
        quote_id=payload.quoteId,
        amount_micro_eur=payload.amountMicroEur,
        available_micro_eur=payload.availableMicroEur,
    )
    return JSONResponse(
        {
            "reservationId": reservation.reservation_id,
            "taskId": reservation.task_id,
            "amountMicroEur": reservation.amount_micro_eur,
            "status": reservation.status,
        },
        status_code=201,
    )


@app.post("/internal/billing/tasks:finalize", tags=["billing"])
async def finalize_paid_task(payload: FinalizePaidTaskRequest) -> JSONResponse:
    body = finance_service.finalize_paid_task(
        idempotency_key=payload.idempotencyKey,
        task_id=payload.taskId,
        task_revision_id=payload.taskRevisionId,
        result_id=payload.resultId,
        verification_id=payload.verificationId,
        price_input=payload.priceInput,
        reward_input=payload.rewardInput,
        refund_micros=payload.refundMicros,
    )
    return JSONResponse(
        {
            "taskId": payload.taskId,
            "chargedMicros": body["chargedMicros"],
            "rewardMicros": body["rewardAccrual"]["workerRewardMicros"],
            "postingId": body["posting"]["postingId"],
            "invoiceLineId": body["invoiceLine"].line_id,
        },
        status_code=202,
    )


@app.get("/internal/billing/reconciliation:daily", tags=["billing"])
async def daily_reconciliation() -> JSONResponse:
    return JSONResponse(finance_service.run_daily_reconciliation(), status_code=200)


class FundCustomerCreditRequest(BaseModel):
    customerId: str
    amountMicroEur: int = Field(gt=0)
    idempotencyKey: str


class StripeWebhookRequest(BaseModel):
    signature: str
    payload: str


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


@app.post("/internal/billing/stripe/credit:fund", tags=["billing", "stripe"])
async def fund_customer_credit(payload: FundCustomerCreditRequest) -> JSONResponse:
    body = payment_provider.fund_customer_credit(
        customer_id=payload.customerId,
        amount_micro_eur=payload.amountMicroEur,
        idempotency_key=payload.idempotencyKey,
    )
    return JSONResponse(body, status_code=201)


@app.post("/internal/billing/stripe/webhooks:ingest", tags=["billing", "stripe"])
async def ingest_stripe_webhook(payload: StripeWebhookRequest) -> JSONResponse:
    secret = StripeSandboxAdapter.resolve_secret_from_arn_env("STRIPE_WEBHOOK_SECRET_ARN")
    body = payment_provider.ingest_webhook(
        payload=payload.payload.encode("utf-8"),
        signature_header=payload.signature,
        webhook_secret=secret,
    )
    return JSONResponse(body, status_code=202)


@app.get("/internal/billing/stripe/reconciliation:provider", tags=["billing", "stripe"])
async def provider_reconciliation() -> JSONResponse:
    return JSONResponse(payment_provider.reconcile_provider_ledger(), status_code=200)


@app.post("/internal/billing/stripe/workers:onboard", tags=["billing", "stripe"])
async def onboard_worker(payload: dict[str, Any]) -> JSONResponse:
    body = payment_provider.onboard_worker(
        worker_id=str(payload["workerId"]),
        country_code=str(payload["countryCode"]),
        idempotency_key=str(payload["idempotencyKey"]),
        sanctions_clear=bool(payload.get("sanctionsClear", True)),
        kyc_complete=bool(payload.get("kycComplete", True)),
    )
    return JSONResponse(body, status_code=201)


@app.get("/internal/billing/financial-close", tags=["billing"])
async def financial_close() -> JSONResponse:
    return JSONResponse(finance_service.financial_close_report(), status_code=200)
