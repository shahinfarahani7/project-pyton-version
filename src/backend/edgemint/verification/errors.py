from __future__ import annotations

from dataclasses import dataclass


@dataclass(slots=True)
class VerificationServiceError(Exception):
    code: str
    status: int
    title: str
    detail: str | None = None


def verification_error(code: str, *, detail: str | None = None) -> VerificationServiceError:
    catalog: dict[str, tuple[int, str]] = {
        "AUTH_INVALID_CREDENTIAL": (401, "Invalid credentials"),
        "CONSENSUS_IDENTITY_COLLISION": (409, "Consensus voter identity collision"),
        "CONSENSUS_QUORUM_NOT_REACHED": (409, "Consensus quorum not reached"),
        "GOLDEN_TASK_FAILED": (409, "Golden task trap failed"),
        "INPUT_SCHEMA_INVALID": (422, "Invalid request"),
        "TENANT_RESOURCE_NOT_FOUND": (404, "Resource not found"),
        "VERIFICATION_CONFLICT": (409, "Conflicting verification results"),
        "VERIFICATION_DISAGREEMENT": (409, "Verification disagreement"),
        "VERIFICATION_POLICY_NOT_ACTIVE": (409, "Verification policy not active"),
    }
    status, title = catalog.get(code, (500, "Verification operation failed"))
    return VerificationServiceError(code=code, status=status, title=title, detail=detail)
