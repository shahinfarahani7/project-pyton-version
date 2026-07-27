from __future__ import annotations

from dataclasses import dataclass


@dataclass(slots=True)
class FinanceServiceError(Exception):
    code: str
    status: int
    title: str
    detail: str | None = None


def finance_error(code: str, *, detail: str | None = None) -> FinanceServiceError:
    catalog: dict[str, tuple[int, str]] = {
        "IDEMPOTENCY_CONFLICT": (409, "Idempotency conflict"),
        "INPUT_SCHEMA_INVALID": (422, "Invalid request"),
        "INSUFFICIENT_CREDIT": (409, "Insufficient credit"),
        "RECONCILIATION_MISMATCH": (409, "Reconciliation mismatch"),
        "TENANT_RESOURCE_NOT_FOUND": (404, "Resource not found"),
    }
    status, title = catalog.get(code, (500, "Finance operation failed"))
    return FinanceServiceError(code=code, status=status, title=title, detail=detail)
