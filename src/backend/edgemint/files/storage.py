from __future__ import annotations

import hashlib
import secrets
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from typing import Protocol
from uuid import UUID

from edgemint.building_blocks.settings import Settings, get_settings
from edgemint.files.errors import file_error
from edgemint.files.policies import workspace_bound_object_key


@dataclass(frozen=True, slots=True)
class ObjectHead:
    size_bytes: int
    sha256: str
    etag: str


@dataclass(frozen=True, slots=True)
class SignedUpload:
    upload_url: str
    object_key: str
    expires_at: datetime


class ObjectStorage(Protocol):
    async def issue_upload_url(
        self,
        *,
        workspace_id: UUID,
        file_id: UUID,
        file_name: str,
        content_type: str,
        size_bytes: int,
        sha256: str,
    ) -> SignedUpload: ...

    async def head_object(self, *, object_key: str) -> ObjectHead | None: ...

    async def put_object(self, *, object_key: str, payload: bytes, sha256: str) -> ObjectHead: ...

    async def delete_object(self, *, object_key: str) -> None: ...

    async def get_object(self, *, object_key: str) -> bytes | None: ...


@dataclass
class InMemoryObjectStorage:
    """Deterministic object storage for contract tests without AWS credentials."""

    settings: Settings = field(default_factory=get_settings)
    _objects: dict[str, tuple[bytes, str]] = field(default_factory=dict)

    async def issue_upload_url(
        self,
        *,
        workspace_id: UUID,
        file_id: UUID,
        file_name: str,
        content_type: str,
        size_bytes: int,
        sha256: str,
    ) -> SignedUpload:
        del content_type, size_bytes
        object_key = workspace_bound_object_key(
            workspace_id=str(workspace_id),
            file_id=str(file_id),
            file_name=file_name,
        )
        token = secrets.token_urlsafe(16)
        expires_at = datetime.now(UTC) + timedelta(seconds=self.settings.file_signed_url_ttl_seconds)
        upload_url = f"memory://upload/{token}?key={object_key}&sha256={sha256}"
        return SignedUpload(upload_url=upload_url, object_key=object_key, expires_at=expires_at)

    async def head_object(self, *, object_key: str) -> ObjectHead | None:
        stored = self._objects.get(object_key)
        if stored is None:
            return None
        payload, sha256 = stored
        etag = hashlib.sha256(payload).hexdigest()[:16]
        return ObjectHead(size_bytes=len(payload), sha256=sha256, etag=etag)

    async def put_object(self, *, object_key: str, payload: bytes, sha256: str) -> ObjectHead:
        digest = hashlib.sha256(payload).hexdigest()
        if digest != sha256.lower():
            raise file_error("FILE_DIGEST_MISMATCH")
        self._objects[object_key] = (payload, digest)
        return ObjectHead(size_bytes=len(payload), sha256=digest, etag=digest[:16])

    async def delete_object(self, *, object_key: str) -> None:
        self._objects.pop(object_key, None)

    async def get_object(self, *, object_key: str) -> bytes | None:
        stored = self._objects.get(object_key)
        if stored is None:
            return None
        payload, _sha256 = stored
        return payload


class S3ObjectStorage:
    """Production adapter placeholder; live AWS wiring is environment-specific."""

    def __init__(self, settings: Settings | None = None) -> None:
        self.settings = settings or get_settings()
        if not self.settings.s3_bucket:
            raise file_error("STORAGE_UNAVAILABLE", detail="EDGEMINT_S3_BUCKET is not configured")

    async def issue_upload_url(
        self,
        *,
        workspace_id: UUID,
        file_id: UUID,
        file_name: str,
        content_type: str,
        size_bytes: int,
        sha256: str,
    ) -> SignedUpload:
        del content_type, size_bytes, sha256
        object_key = workspace_bound_object_key(
            workspace_id=str(workspace_id),
            file_id=str(file_id),
            file_name=file_name,
        )
        expires_at = datetime.now(UTC) + timedelta(seconds=self.settings.file_signed_url_ttl_seconds)
        bucket = self.settings.s3_bucket
        assert bucket is not None
        upload_url = f"https://{bucket}.s3.amazonaws.com/{object_key}?X-Amz-Expires={self.settings.file_signed_url_ttl_seconds}"
        return SignedUpload(upload_url=upload_url, object_key=object_key, expires_at=expires_at)

    async def head_object(self, *, object_key: str) -> ObjectHead | None:
        del object_key
        raise file_error("STORAGE_UNAVAILABLE", detail="S3 head_object requires live AWS integration")

    async def put_object(self, *, object_key: str, payload: bytes, sha256: str) -> ObjectHead:
        del object_key, payload, sha256
        raise file_error("STORAGE_UNAVAILABLE", detail="S3 put_object requires live AWS integration")

    async def delete_object(self, *, object_key: str) -> None:
        del object_key
        raise file_error("STORAGE_UNAVAILABLE", detail="S3 delete_object requires live AWS integration")

    async def get_object(self, *, object_key: str) -> bytes | None:
        del object_key
        raise file_error("STORAGE_UNAVAILABLE", detail="S3 get_object requires live AWS integration")


def get_object_storage(settings: Settings | None = None) -> ObjectStorage:
    active = settings or get_settings()
    if active.file_storage_backend == "s3":
        return S3ObjectStorage(active)
    return InMemoryObjectStorage(active)
