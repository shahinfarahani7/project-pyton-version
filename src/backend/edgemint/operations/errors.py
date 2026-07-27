from __future__ import annotations

from dataclasses import dataclass


@dataclass(slots=True)
class OperationsServiceError(Exception):
    code: str
    status: int
    title: str
    detail: str | None = None


def operations_error(code: str, *, detail: str | None = None) -> OperationsServiceError:
    catalog: dict[str, tuple[int, str]] = {
        "APPROVAL_SELF_DENIED": (403, "Self-approval denied"),
        "AUTH_SCOPE_REQUIRED": (403, "Authorization scope required"),
        "BREAK_GLASS_EXPIRED": (409, "Break-glass session expired"),
        "ETAG_MISMATCH": (412, "Concurrency token mismatch"),
        "IDEMPOTENCY_CONFLICT": (409, "Idempotency conflict"),
        "INPUT_SCHEMA_INVALID": (422, "Invalid request"),
        "PENDING_APPROVAL_REQUIRED": (409, "Independent approval required"),
        "TENANT_RESOURCE_NOT_FOUND": (404, "Resource not found"),
    }
    status, title = catalog.get(code, (500, "Operations action failed"))
    return OperationsServiceError(code=code, status=status, title=title, detail=detail)
