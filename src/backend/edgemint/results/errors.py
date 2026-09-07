from __future__ import annotations

from dataclasses import dataclass


@dataclass(slots=True)
class ResultServiceError(Exception):
    code: str
    status: int
    title: str
    detail: str | None = None


def result_error(code: str, *, detail: str | None = None) -> ResultServiceError:
    catalog: dict[str, tuple[int, str]] = {
        "ASSIGNMENT_STALE_FENCE": (409, "Stale fence token"),
        "AUTH_INVALID_CREDENTIAL": (401, "Invalid credentials"),
        "DUPLICATE_RESULT": (409, "Duplicate result submission"),
        "IDEMPOTENCY_CONFLICT": (409, "Idempotency conflict"),
        "INPUT_DIGEST_MISMATCH": (409, "Input digest mismatch"),
        "INPUT_SCHEMA_INVALID": (422, "Invalid request"),
        "LEASE_TOKEN_MISMATCH": (409, "Lease token mismatch"),
        "MODEL_DIGEST_MISMATCH": (409, "Model digest mismatch"),
        "RESULT_OVERSIZED": (422, "Result payload too large"),
        "RESULT_SCHEMA_INVALID": (422, "Result schema invalid"),
        "RESULT_VALIDATION_FAILED": (422, "Result validation failed"),
        "RESULT_SIGNATURE_INVALID": (403, "Result signature invalid"),
        "TENANT_RESOURCE_NOT_FOUND": (404, "Resource not found"),
    }
    status, title = catalog.get(code, (500, "Result operation failed"))
    return ResultServiceError(code=code, status=status, title=title, detail=detail)
