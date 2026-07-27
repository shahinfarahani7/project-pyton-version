from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class TaskServiceError(Exception):
    code: str
    status: int
    title: str
    detail: str | None = None


def task_error(code: str, *, detail: str | None = None) -> TaskServiceError:
    catalog: dict[str, tuple[int, str]] = {
        "CHANGE_REASON_REQUIRED": (422, "Change reason required"),
        "FILE_NOT_READY": (409, "Input file not ready"),
        "IDEMPOTENCY_CONFLICT": (409, "Idempotency conflict"),
        "INPUT_SCHEMA_INVALID": (422, "Invalid request"),
        "INSUFFICIENT_CREDIT": (409, "Insufficient prepaid credit"),
        "QUOTE_EXPIRED": (409, "Quote expired"),
        "TASK_NOT_CANCELLABLE": (409, "Task cannot be cancelled"),
        "TASK_REVISION_IMMUTABLE": (409, "Task revision is immutable"),
        "TASK_TYPE_NOT_ACTIVE": (422, "Task type not active"),
        "TENANT_RESOURCE_NOT_FOUND": (404, "Resource not found"),
        "UNSUPPORTED_TASK_CONFIGURATION": (422, "Unsupported task configuration"),
        "VERSION_CONFLICT": (412, "Version conflict"),
        "ADMISSION_LIMIT_EXCEEDED": (429, "Workspace admission limit exceeded"),
    }
    status, title = catalog.get(code, (500, "Task operation failed"))
    return TaskServiceError(code=code, status=status, title=title, detail=detail)
