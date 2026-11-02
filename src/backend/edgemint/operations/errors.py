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
        "AUTH_REQUIRED": (401, "Operator authentication required"),
        "AUTH_SCOPE_REQUIRED": (403, "Authorization scope required"),
        "CSRF_INVALID": (403, "CSRF token missing or invalid"),
        "DEV_LOGIN_DISABLED": (404, "Development sign-in disabled"),
        "MFA_REQUIRED": (403, "MFA verification required"),
        "PORTAL_SESSION_REQUIRED": (401, "Sign in to the portal first"),
        "SSO_NOT_CONFIGURED": (501, "Operator SSO not configured"),
        "TASK_MONITOR_UNAVAILABLE": (501, "Task monitor not available in this environment"),
        "UPSTREAM_UNAVAILABLE": (503, "Upstream service unavailable"),
        "BREAK_GLASS_EXPIRED": (409, "Break-glass session expired"),
        "ETAG_MISMATCH": (412, "Concurrency token mismatch"),
        "IDEMPOTENCY_CONFLICT": (409, "Idempotency conflict"),
        "INPUT_SCHEMA_INVALID": (422, "Invalid request"),
        "PENDING_APPROVAL_REQUIRED": (409, "Independent approval required"),
        "TENANT_RESOURCE_NOT_FOUND": (404, "Resource not found"),
    }
    status, title = catalog.get(code, (500, "Operations action failed"))
    return OperationsServiceError(code=code, status=status, title=title, detail=detail)
