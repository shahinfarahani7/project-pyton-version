from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class FileServiceError(Exception):
    code: str
    status: int
    title: str
    detail: str | None = None


def file_error(code: str, *, detail: str | None = None) -> FileServiceError:
    catalog: dict[str, tuple[int, str]] = {
        "AUTH_SCOPE_REQUIRED": (403, "Required permission missing"),
        "CONTENT_TYPE_NOT_ALLOWED": (422, "Content type not allowed"),
        "DELETION_EVIDENCE_FAILED": (409, "Deletion evidence failed"),
        "FILE_DIGEST_MISMATCH": (409, "File digest mismatch"),
        "IDEMPOTENCY_CONFLICT": (409, "Idempotency conflict"),
        "INPUT_SCHEMA_INVALID": (422, "Invalid request"),
        "LEGAL_HOLD_ACTIVE": (409, "Legal hold active"),
        "MALWARE_DETECTED": (409, "Malware detected"),
        "STORAGE_UNAVAILABLE": (503, "Object storage unavailable"),
        "TENANT_RESOURCE_NOT_FOUND": (404, "Resource not found"),
        "UPLOAD_INCOMPLETE": (409, "Upload incomplete"),
        "UPLOAD_SIZE_INVALID": (422, "Upload size invalid"),
    }
    status, title = catalog.get(code, (500, "File operation failed"))
    return FileServiceError(code=code, status=status, title=title, detail=detail)
