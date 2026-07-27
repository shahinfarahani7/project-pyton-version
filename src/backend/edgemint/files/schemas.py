from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field


class UploadIntentRequest(BaseModel):
    workspaceId: UUID
    fileName: str = Field(max_length=255)
    contentType: str
    sizeBytes: int = Field(ge=1)
    sha256: str = Field(pattern=r"^[a-f0-9]{64}$")


class FileResponse(BaseModel):
    id: str
    status: str
    sizeBytes: int
    sha256: str
    uploadUrl: str | None = None
    expiresAt: datetime | None = None


class CompleteUploadRequest(BaseModel):
    etag: str = Field(min_length=1)


class DeleteFileResponse(BaseModel):
    operationId: str
    accepted: bool
    status: Literal["scheduled"]
    occurredAt: datetime


class CreateUploadIntentResponse(FileResponse):
    pass


class CompleteFileUploadResponse(FileResponse):
    pass


class GetFileResponse(FileResponse):
    pass
