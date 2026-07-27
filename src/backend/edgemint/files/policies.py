from __future__ import annotations

from edgemint.building_blocks.settings import Settings, get_settings
from edgemint.files.errors import FileServiceError, file_error

DEFAULT_ALLOWED_CONTENT_TYPES = frozenset(
    {
        "application/json",
        "application/pdf",
        "application/octet-stream",
        "image/jpeg",
        "image/png",
        "text/plain",
    }
)


def validate_upload_request(
    *,
    content_type: str,
    size_bytes: int,
    sha256: str,
    settings: Settings | None = None,
) -> None:
    active = settings or get_settings()
    if size_bytes < 1 or size_bytes > active.file_max_upload_bytes:
        raise file_error("UPLOAD_SIZE_INVALID", detail="sizeBytes exceeds workspace upload limit")
    normalized_type = content_type.split(";", 1)[0].strip().lower()
    if normalized_type not in DEFAULT_ALLOWED_CONTENT_TYPES:
        raise file_error("CONTENT_TYPE_NOT_ALLOWED", detail=f"contentType {content_type!r} is not permitted")
    if len(sha256) != 64 or any(ch not in "0123456789abcdef" for ch in sha256.lower()):
        raise FileServiceError(
            code="INPUT_SCHEMA_INVALID",
            status=422,
            title="Invalid request",
            detail="sha256 must be 64 lowercase hex characters",
        )


def workspace_bound_object_key(*, workspace_id: str, file_id: str, file_name: str) -> str:
    safe_name = file_name.replace("/", "_").replace("\\", "_")[:200] or "object"
    return f"workspaces/{workspace_id}/files/{file_id}/{safe_name}"
