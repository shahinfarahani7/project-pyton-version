from __future__ import annotations

from dataclasses import dataclass


@dataclass(slots=True)
class RouterServiceError(Exception):
    code: str
    status: int
    title: str
    detail: str | None = None


def router_error(code: str, *, detail: str | None = None) -> RouterServiceError:
    catalog: dict[str, tuple[int, str]] = {
        "ASSIGNMENT_STALE_FENCE": (409, "Stale fence token"),
        "AUTH_INVALID_CREDENTIAL": (401, "Invalid credentials"),
        "DEADLINE_EXPIRED": (409, "Deadline expired"),
        "IDEMPOTENCY_CONFLICT": (409, "Idempotency conflict"),
        "INPUT_SCHEMA_INVALID": (422, "Invalid request"),
        "LEASE_RENEWAL_REJECTED": (409, "Lease renewal rejected"),
        "NO_CAPACITY": (409, "No eligible worker capacity"),
        "ROUTING_CLAIM_INVALID": (409, "Routing claim invalid"),
        "TENANT_RESOURCE_NOT_FOUND": (404, "Resource not found"),
        "WORKER_CAPACITY_EXHAUSTED": (409, "Worker capacity exhausted"),
        "WORKER_NOT_ELIGIBLE": (409, "Worker not eligible"),
    }
    status, title = catalog.get(code, (500, "Router operation failed"))
    return RouterServiceError(code=code, status=status, title=title, detail=detail)
