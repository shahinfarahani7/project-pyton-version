from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class WorkerServiceError(Exception):
    code: str
    status: int
    title: str
    detail: str | None = None


def worker_error(code: str, *, detail: str | None = None) -> WorkerServiceError:
    catalog: dict[str, tuple[int, str]] = {
        "ATTESTATION_INVALID": (403, "Attestation invalid"),
        "AUTH_INVALID_CREDENTIAL": (401, "Invalid credentials"),
        "AUTH_SCOPE_REQUIRED": (403, "Required permission missing"),
        "CHALLENGE_EXPIRED": (409, "Challenge expired"),
        "CONSENT_MISMATCH": (409, "Consent policy mismatch"),
        "DEVICE_KEY_MISMATCH": (409, "Device key mismatch"),
        "EMULATOR_POLICY_BREACH": (403, "Emulator not permitted"),
        "HEARTBEAT_SEQUENCE_INVALID": (409, "Heartbeat sequence invalid"),
        "IDEMPOTENCY_CONFLICT": (409, "Idempotency conflict"),
        "INPUT_SCHEMA_INVALID": (422, "Invalid request"),
        "LEASE_CREDENTIAL_UNAVAILABLE": (503, "Lease credential unavailable"),
        "LEASE_RENEWAL_REJECTED": (409, "Lease renewal rejected"),
        "LEASE_TOKEN_MISMATCH": (409, "Lease token mismatch"),
        "ASSIGNMENT_STALE_FENCE": (409, "Assignment fence is stale"),
        "RESULT_SCHEMA_INVALID": (422, "Result schema invalid"),
        "RESULT_VALIDATION_FAILED": (422, "Result validation failed"),
        "CHECKPOINT_NOT_SUPPORTED": (422, "Checkpoint not supported for task type"),
        "TENANT_RESOURCE_NOT_FOUND": (404, "Resource not found"),
        "VERSION_CONFLICT": (412, "Version conflict"),
        "WORKER_NOT_READY": (409, "Worker not ready for assignments"),
        "WORKER_QUARANTINED": (403, "Worker quarantined"),
    }
    status, title = catalog.get(code, (500, "Worker operation failed"))
    return WorkerServiceError(code=code, status=status, title=title, detail=detail)
