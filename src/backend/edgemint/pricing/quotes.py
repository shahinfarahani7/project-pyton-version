from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

from pydantic import BaseModel, Field

from edgemint.building_blocks.ids import public_id
from edgemint.pricing.engine import PriceInput, PricingEngine, PricingRejectedError
from edgemint.pricing.policy import load_price_policy

TASK_TYPE_ALIASES = {
    "document-ocr": "document.ocr",
    "document-extract": "document.extract",
    "document-verify": "document.verify",
    "image-classify": "image.classify",
    "image-detect": "image.detect",
    "vision-analyze": "vision.analyze",
    "audio-transcribe": "audio.transcribe",
    "text-translate": "text.translate",
    "text-generate": "text.generate",
    "text-embedding": "text.embedding",
}

PRIORITY_MAP = {
    "batch": "batch",
    "standard": "standard",
    "priority": "priority",
    "realtime": "realtime",
}

VERIFICATION_MAP = {
    "standard": "standard",
    "verified": "verified",
    "consensus": "consensus",
    "enterprise": "enterprise",
    "human_review": "human_review",
}


class TaskConfiguration(BaseModel):
    outputFormat: str | None = None
    verificationLevel: str = "standard"
    priority: str = "standard"
    regionPolicy: str = "any_allowed"
    retentionDays: int = 0
    parameters: dict[str, Any] = Field(default_factory=dict)


class CreateQuoteRequest(BaseModel):
    workspaceId: UUID
    taskType: str
    input: dict[str, Any] = Field(default_factory=dict)
    configuration: TaskConfiguration = Field(default_factory=TaskConfiguration)
    quantity: int = Field(default=1, ge=1)
    plan: str = "developer"
    region: str = "eu-central"
    executionPolicy: str = "edge_preferred"
    retention: str = "default"
    contractDiscountBps: int = Field(default=0, ge=0, le=10_000)
    promotionDiscountBps: int = Field(default=0, ge=0, le=10_000)
    expectedCostMicros: int | None = Field(default=None, ge=0)
    stressedCostMicros: int | None = Field(default=None, ge=0)
    subsidyReserved: bool = False


class QuoteBreakdownItem(BaseModel):
    code: str
    amountMicros: int


class QuotePrice(BaseModel):
    amountMicros: int
    currency: str


class CreateQuoteResponse(BaseModel):
    id: str
    expiresAt: datetime
    price: QuotePrice
    priceBookVersion: str
    breakdown: list[QuoteBreakdownItem]


@dataclass
class QuoteService:
    engine: PricingEngine

    @classmethod
    def default(cls) -> QuoteService:
        return cls(engine=PricingEngine(load_price_policy()))

    def build_price_input(self, request: CreateQuoteRequest) -> PriceInput:
        canonical_task_type = TASK_TYPE_ALIASES.get(request.taskType, request.taskType.replace("-", "."))
        verification = VERIFICATION_MAP.get(
            request.configuration.verificationLevel,
            request.configuration.verificationLevel,
        )
        priority = PRIORITY_MAP.get(request.configuration.priority, request.configuration.priority)
        return PriceInput(
            task_type=canonical_task_type,
            quantity=request.quantity,
            plan=request.plan,
            priority=priority,
            verification=verification,
            region=request.region,
            execution_policy=request.executionPolicy,
            retention=request.retention,
            contract_discount_bps=request.contractDiscountBps,
            promotion_discount_bps=request.promotionDiscountBps,
            expected_cost_micros=request.expectedCostMicros,
            stressed_cost_micros=request.stressedCostMicros,
            subsidy_reserved=request.subsidyReserved,
        )

    def create_quote(self, request: CreateQuoteRequest) -> CreateQuoteResponse:
        price_input = self.build_price_input(request)
        result = self.engine.quote(price_input)
        expires_at = datetime.now(UTC) + timedelta(seconds=self.engine.policy.quote_ttl_seconds)
        breakdown = [
            QuoteBreakdownItem(code="base", amountMicros=result.base_micros),
            *[
                QuoteBreakdownItem(
                    code=f"{step['modifier']}:{step['value']}",
                    amountMicros=step["runningMicros"],
                )
                for step in result.steps
            ],
        ]
        if result.minimum_applied:
            breakdown.append(
                QuoteBreakdownItem(
                    code="minimum_charge",
                    amountMicros=result.charge_micros,
                )
            )
        return CreateQuoteResponse(
            id=public_id("qte"),
            expiresAt=expires_at,
            price=QuotePrice(amountMicros=result.charge_micros, currency=result.currency),
            priceBookVersion=result.policy_version,
            breakdown=breakdown,
        )


def map_pricing_error(exc: Exception) -> tuple[str, int]:
    if isinstance(exc, PricingRejectedError):
        return exc.code, 409
    if isinstance(exc, KeyError):
        return "UNSUPPORTED_TASK_CONFIGURATION", 422
    if isinstance(exc, ValueError):
        message = str(exc)
        if "NEGATIVE" in message or "QUANTITY" in message:
            return "INPUT_SCHEMA_INVALID", 422
        if "OVERFLOW" in message:
            return "INPUT_SCHEMA_INVALID", 422
    return "INPUT_SCHEMA_INVALID", 422
