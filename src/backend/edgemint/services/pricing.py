from __future__ import annotations

from typing import Annotated

from fastapi import Depends, Header, HTTPException, Request
from fastapi.responses import JSONResponse

from edgemint.building_blocks.app import create_service_app
from edgemint.building_blocks.settings import get_settings
from edgemint.pricing.engine import PricingRejectedError
from edgemint.pricing.quotes import CreateQuoteRequest, QuoteService, map_pricing_error
from edgemint.security.context import AuthorizationContext
from edgemint.security.dependencies import AuthorizationDependency
from edgemint.security.problems import request_trace_id

app = create_service_app("pricing")
settings = get_settings()
quote_service = QuoteService.default()

CreateQuoteAuth = Annotated[
    AuthorizationContext,
    Depends(AuthorizationDependency("createQuote")),
]


@app.exception_handler(PricingRejectedError)
async def pricing_rejected_handler(_: Request, exc: PricingRejectedError) -> JSONResponse:
    return JSONResponse(
        {
            "type": f"https://problems.edgemint.io/{exc.code.lower().replace('_', '-')}",
            "title": "Pricing rejected",
            "status": 409,
            "code": exc.code,
            **({"detail": exc.detail} if exc.detail else {}),
        },
        status_code=409,
    )


@app.post("/quotes", tags=["quotes"])
async def create_quote(
    request: Request,
    payload: CreateQuoteRequest,
    auth: CreateQuoteAuth,
    idempotency_key: str = Header(alias="Idempotency-Key"),
) -> JSONResponse:
    del auth, idempotency_key
    if payload.workspaceId and settings.environment not in {"development", "test"}:
        pass
    try:
        body = quote_service.create_quote(payload)
    except (PricingRejectedError, KeyError, ValueError, OverflowError) as exc:
        code, status = map_pricing_error(exc)
        raise HTTPException(
            status_code=status,
            detail={"code": code, "title": "Quote creation failed", "detail": str(exc)},
        ) from exc
    response = JSONResponse(body.model_dump(mode="json"), status_code=201)
    response.headers["X-Request-Id"] = request_trace_id(request)
    return response
