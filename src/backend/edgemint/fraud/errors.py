from __future__ import annotations

from dataclasses import dataclass


@dataclass(slots=True)
class FraudServiceError(Exception):
    code: str
    status: int
    title: str
    detail: str | None = None


def fraud_error(code: str, *, detail: str | None = None) -> FraudServiceError:
    catalog: dict[str, tuple[int, str]] = {
        "APPEAL_NOT_ALLOWED": (409, "Appeal not allowed"),
        "CASE_NOT_FOUND": (404, "Fraud case not found"),
        "INPUT_SCHEMA_INVALID": (422, "Invalid request"),
        "PRIVACY_RECORD_RETAINED": (409, "Record retained for compliance"),
        "REVERSAL_NOT_PERMITTED": (409, "Reversal not permitted"),
    }
    status, title = catalog.get(code, (500, "Fraud operation failed"))
    return FraudServiceError(code=code, status=status, title=title, detail=detail)
