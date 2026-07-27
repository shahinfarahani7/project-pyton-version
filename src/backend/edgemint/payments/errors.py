from __future__ import annotations

from dataclasses import dataclass


@dataclass(slots=True)
class PaymentProviderError(Exception):
    code: str
    status: int
    title: str
    detail: str | None = None


def payment_error(code: str, *, detail: str | None = None) -> PaymentProviderError:
    catalog: dict[str, tuple[int, str]] = {
        "COUNTRY_NOT_SUPPORTED": (422, "Country not supported"),
        "IDEMPOTENCY_CONFLICT": (409, "Idempotency conflict"),
        "INPUT_SCHEMA_INVALID": (422, "Invalid request"),
        "KYC_INCOMPLETE": (422, "KYC incomplete"),
        "PAYOUT_FAILED": (409, "Payout failed"),
        "PROVIDER_RECONCILIATION_MISMATCH": (409, "Provider reconciliation mismatch"),
        "SANCTIONS_HOLD": (403, "Sanctions hold"),
        "WEBHOOK_SIGNATURE_INVALID": (401, "Webhook signature invalid"),
    }
    status, title = catalog.get(code, (500, "Payment provider operation failed"))
    return PaymentProviderError(code=code, status=status, title=title, detail=detail)
