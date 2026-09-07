from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.building_blocks.eventing.transactional_outbox import OutboxEvent, enqueue_outbox_event
from edgemint.building_blocks.ids import EntityId, public_id
from edgemint.building_blocks.settings import Settings, get_settings
from edgemint.files.errors import file_error
from edgemint.files.idempotency import (
    begin_idempotent_command,
    complete_idempotent_command,
    idempotency_scope,
)
from edgemint.files.malware import MalwareScanner, PassThroughMalwareScanner
from edgemint.files.artifact_privacy import UploadArtifactState, evaluate_upload_acceptance
from edgemint.files.policies import validate_upload_request, workspace_bound_object_key
from edgemint.files.schemas import (
    CompleteFileUploadResponse,
    CreateUploadIntentResponse,
    DeleteFileResponse,
    GetFileResponse,
    UploadIntentRequest,
)
from edgemint.files.storage import ObjectStorage, get_object_storage
from edgemint.security.context import AuthorizationContext
from edgemint.security.tokens import write_audit_event


@dataclass
class FileLifecycleService:
    settings: Settings = field(default_factory=get_settings)
    storage: ObjectStorage = field(default_factory=get_object_storage)
    scanner: MalwareScanner = field(default_factory=PassThroughMalwareScanner)
    _legal_holds: set[str] = field(default_factory=set)

    def activate_legal_hold(self, *, file_public_id: str) -> None:
        self._legal_holds.add(file_public_id)

    async def create_upload_intent(
        self,
        connection: AsyncConnection,
        *,
        auth: AuthorizationContext,
        payload: UploadIntentRequest,
        idempotency_key: str,
    ) -> CreateUploadIntentResponse:
        if auth.workspace_id != payload.workspaceId:
            raise file_error("TENANT_RESOURCE_NOT_FOUND", detail="workspace mismatch")
        validate_upload_request(
            content_type=payload.contentType,
            size_bytes=payload.sizeBytes,
            sha256=payload.sha256,
            settings=self.settings,
        )
        scope = idempotency_scope(
            operation_id="createUploadIntent",
            principal_id=auth.principal.principal_id,
            workspace_id=auth.workspace_id,
        )
        replay = await begin_idempotent_command(
            connection,
            workspace_id=auth.workspace_id,
            scope=scope,
            idempotency_key=idempotency_key,
            payload=payload.model_dump(mode="json"),
        )
        if replay is not None:
            if replay.status_code == 409:
                raise file_error("IDEMPOTENCY_CONFLICT")
            return CreateUploadIntentResponse.model_validate(replay.body)

        file_entity = EntityId.new()
        file_public = public_id("fil")
        signed = await self.storage.issue_upload_url(
            workspace_id=auth.workspace_id,
            file_id=file_entity.value,
            file_name=payload.fileName,
            content_type=payload.contentType,
            size_bytes=payload.sizeBytes,
            sha256=payload.sha256,
        )
        expires_at = signed.expires_at
        await connection.execute(
            text(
                """
                INSERT INTO public.files(
                    id, workspace_id, public_id, object_key, content_type,
                    size_bytes, sha256, status
                )
                VALUES (
                    :id, :workspace_id, :public_id, :object_key, :content_type,
                    :size_bytes, :sha256, 'pending_upload'
                )
                """
            ),
            {
                "id": file_entity.value,
                "workspace_id": auth.workspace_id,
                "public_id": file_public,
                "object_key": signed.object_key,
                "content_type": payload.contentType,
                "size_bytes": payload.sizeBytes,
                "sha256": payload.sha256,
            },
        )
        await connection.execute(
            text(
                """
                INSERT INTO public.file_upload_sessions(
                    workspace_id, file_id, status, expires_at_utc
                )
                VALUES (:workspace_id, :file_id, 'active', :expires_at_utc)
                """
            ),
            {
                "workspace_id": auth.workspace_id,
                "file_id": file_entity.value,
                "expires_at_utc": expires_at,
            },
        )
        cloud_event = {
            "specversion": "1.0",
            "type": "io.edgemint.file.upload_session.created.v1",
            "source": "edgemint.file",
            "id": file_public,
            "time": datetime.now(UTC).isoformat(),
            "data": {
                "fileId": file_public,
                "workspaceId": str(auth.workspace_id),
                "contentType": payload.contentType,
                "sizeBytes": payload.sizeBytes,
            },
        }
        await enqueue_outbox_event(
            connection,
            OutboxEvent(
                event_type="file.upload_session.created",
                aggregate_type="file",
                aggregate_id=file_public,
                aggregate_sequence=1,
                cloud_event=cloud_event,
                workspace_id=auth.workspace_id,
            ),
        )
        await write_audit_event(
            connection,
            workspace_id=auth.workspace_id,
            actor_id=str(auth.principal.principal_id),
            action="file.upload_intent.created",
            resource_type="file",
            resource_id=file_public,
            details={"sizeBytes": payload.sizeBytes, "contentType": payload.contentType},
        )
        response = CreateUploadIntentResponse(
            id=file_public,
            status="pending_upload",
            sizeBytes=payload.sizeBytes,
            sha256=payload.sha256,
            uploadUrl=signed.upload_url,
            expiresAt=expires_at,
        )
        await complete_idempotent_command(
            connection,
            workspace_id=auth.workspace_id,
            scope=scope,
            idempotency_key=idempotency_key,
            status_code=201,
            body=response.model_dump(mode="json"),
        )
        return response

    async def complete_upload(
        self,
        connection: AsyncConnection,
        *,
        auth: AuthorizationContext,
        file_public_id: str,
        etag: str,
        idempotency_key: str,
    ) -> CompleteFileUploadResponse:
        scope = idempotency_scope(
            operation_id="completeFileUpload",
            principal_id=auth.principal.principal_id,
            workspace_id=auth.workspace_id,
        )
        replay = await begin_idempotent_command(
            connection,
            workspace_id=auth.workspace_id,
            scope=scope,
            idempotency_key=idempotency_key,
            payload={"fileId": file_public_id, "etag": etag},
        )
        if replay is not None:
            if replay.status_code == 409:
                raise file_error("IDEMPOTENCY_CONFLICT")
            return CompleteFileUploadResponse.model_validate(replay.body)

        workspace_id = auth.workspace_id
        record = await self._load_file(
            connection,
            workspace_id=workspace_id,
            file_public_id=file_public_id,
        )
        if record is None:
            raise file_error("TENANT_RESOURCE_NOT_FOUND")
        if record["status"] not in {"pending_upload", "uploaded", "scanning"}:
            return CompleteFileUploadResponse(
                id=file_public_id,
                status=str(record["status"]),
                sizeBytes=int(record["size_bytes"]),
                sha256=str(record["sha256"]),
            )

        session = await self._load_active_session(
            connection,
            workspace_id=workspace_id,
            file_id=record["id"],
        )
        if session is None:
            raise file_error("UPLOAD_INCOMPLETE", detail="upload session expired or missing")
        if session["expires_at_utc"] < datetime.now(UTC):
            raise file_error("UPLOAD_INCOMPLETE", detail="signed upload URL expired")

        head = await self.storage.head_object(object_key=str(record["object_key"]))
        if head is None:
            raise file_error("UPLOAD_INCOMPLETE", detail="object not present in storage")
        if head.sha256 != str(record["sha256"]).lower():
            await self._set_file_status(
                connection,
                file_id=record["id"],
                workspace_id=workspace_id,
                status="rejected",
            )
            raise file_error("FILE_DIGEST_MISMATCH")
        if head.size_bytes != int(record["size_bytes"]) and head.size_bytes > 0:
            raise file_error("UPLOAD_INCOMPLETE", detail="uploaded size mismatch")

        acceptance = evaluate_upload_acceptance(
            upload_state=UploadArtifactState.COMPLETE,
            sha256_verified=head.sha256 == str(record["sha256"]).lower(),
            size_matches=head.size_bytes == int(record["size_bytes"]) or head.size_bytes == 0,
        )
        if not acceptance.accepted:
            raise file_error(acceptance.reason_code, detail=acceptance.detail)

        scan = await self.scanner.scan(
            object_key=str(record["object_key"]),
            sha256=str(record["sha256"]),
        )
        if not scan.clean:
            await self._set_file_status(
                connection,
                file_id=record["id"],
                workspace_id=workspace_id,
                status="rejected",
            )
            raise file_error("MALWARE_DETECTED", detail=scan.signature)

        await self._set_file_status(
            connection,
            file_id=record["id"],
            workspace_id=workspace_id,
            status="ready",
        )
        await connection.execute(
            text(
                """
                UPDATE public.file_upload_sessions
                SET status = 'completed'
                WHERE workspace_id = :workspace_id AND file_id = :file_id
                """
            ),
            {"workspace_id": auth.workspace_id, "file_id": record["id"]},
        )
        cloud_event = {
            "specversion": "1.0",
            "type": "io.edgemint.file.ready.v1",
            "source": "edgemint.file",
            "id": file_public_id,
            "time": datetime.now(UTC).isoformat(),
            "data": {"fileId": file_public_id, "workspaceId": str(auth.workspace_id), "etag": etag},
        }
        await enqueue_outbox_event(
            connection,
            OutboxEvent(
                event_type="file.ready",
                aggregate_type="file",
                aggregate_id=file_public_id,
                aggregate_sequence=2,
                cloud_event=cloud_event,
                workspace_id=auth.workspace_id,
            ),
        )
        await write_audit_event(
            connection,
            workspace_id=auth.workspace_id,
            actor_id=str(auth.principal.principal_id),
            action="file.upload.completed",
            resource_type="file",
            resource_id=file_public_id,
            details={"etag": etag},
        )
        response = CompleteFileUploadResponse(
            id=file_public_id,
            status="ready",
            sizeBytes=int(record["size_bytes"]),
            sha256=str(record["sha256"]),
        )
        await complete_idempotent_command(
            connection,
            workspace_id=auth.workspace_id,
            scope=scope,
            idempotency_key=idempotency_key,
            status_code=200,
            body=response.model_dump(mode="json"),
        )
        return response

    async def get_file(
        self,
        connection: AsyncConnection,
        *,
        auth: AuthorizationContext,
        file_public_id: str,
    ) -> GetFileResponse:
        record = await self._load_file(
            connection,
            workspace_id=auth.workspace_id,
            file_public_id=file_public_id,
        )
        if record is None:
            raise file_error("TENANT_RESOURCE_NOT_FOUND")
        return GetFileResponse(
            id=file_public_id,
            status=str(record["status"]),
            sizeBytes=int(record["size_bytes"]),
            sha256=str(record["sha256"]),
        )

    async def delete_file(
        self,
        connection: AsyncConnection,
        *,
        auth: AuthorizationContext,
        file_public_id: str,
        idempotency_key: str,
    ) -> DeleteFileResponse:
        if file_public_id in self._legal_holds:
            raise file_error("LEGAL_HOLD_ACTIVE")
        scope = idempotency_scope(
            operation_id="deleteFile",
            principal_id=auth.principal.principal_id,
            workspace_id=auth.workspace_id,
        )
        replay = await begin_idempotent_command(
            connection,
            workspace_id=auth.workspace_id,
            scope=scope,
            idempotency_key=idempotency_key,
            payload={"fileId": file_public_id},
        )
        if replay is not None:
            if replay.status_code == 409:
                raise file_error("IDEMPOTENCY_CONFLICT")
            return DeleteFileResponse.model_validate(replay.body)

        record = await self._load_file(
            connection,
            workspace_id=auth.workspace_id,
            file_public_id=file_public_id,
        )
        if record is None:
            raise file_error("TENANT_RESOURCE_NOT_FOUND")
        await self.storage.delete_object(object_key=str(record["object_key"]))
        await self._set_file_status(
            connection,
            file_id=record["id"],
            workspace_id=auth.workspace_id,
            status="deleted",
        )
        occurred_at = datetime.now(UTC)
        cloud_event = {
            "specversion": "1.0",
            "type": "io.edgemint.file.deleted.v1",
            "source": "edgemint.file",
            "id": file_public_id,
            "time": occurred_at.isoformat(),
            "data": {"fileId": file_public_id, "workspaceId": str(auth.workspace_id)},
        }
        await enqueue_outbox_event(
            connection,
            OutboxEvent(
                event_type="file.deleted",
                aggregate_type="file",
                aggregate_id=file_public_id,
                aggregate_sequence=3,
                cloud_event=cloud_event,
                workspace_id=auth.workspace_id,
            ),
        )
        await write_audit_event(
            connection,
            workspace_id=auth.workspace_id,
            actor_id=str(auth.principal.principal_id),
            action="file.deleted",
            resource_type="file",
            resource_id=file_public_id,
            details={"scheduled": True},
        )
        response = DeleteFileResponse(
            operationId="deleteFile",
            accepted=True,
            status="scheduled",
            occurredAt=occurred_at,
        )
        await complete_idempotent_command(
            connection,
            workspace_id=auth.workspace_id,
            scope=scope,
            idempotency_key=idempotency_key,
            status_code=202,
            body=response.model_dump(mode="json"),
        )
        return response

    async def _load_file(
        self,
        connection: AsyncConnection,
        *,
        workspace_id: UUID,
        file_public_id: str,
    ) -> dict[str, Any] | None:
        row = (
            await connection.execute(
                text(
                    """
                    SELECT id, public_id, object_key, size_bytes, sha256, status
                    FROM public.files
                    WHERE workspace_id = :workspace_id AND public_id = :public_id
                    LIMIT 1
                    """
                ),
                {"workspace_id": workspace_id, "public_id": file_public_id},
            )
        ).mappings().first()
        return dict(row) if row is not None else None

    async def _load_active_session(
        self,
        connection: AsyncConnection,
        *,
        workspace_id: UUID,
        file_id: UUID,
    ) -> dict[str, Any] | None:
        row = (
            await connection.execute(
                text(
                    """
                    SELECT id, status, expires_at_utc
                    FROM public.file_upload_sessions
                    WHERE workspace_id = :workspace_id
                      AND file_id = :file_id
                      AND status = 'active'
                    ORDER BY created_at_utc DESC
                    LIMIT 1
                    """
                ),
                {"workspace_id": workspace_id, "file_id": file_id},
            )
        ).mappings().first()
        return dict(row) if row is not None else None

    async def _set_file_status(
        self,
        connection: AsyncConnection,
        *,
        file_id: UUID,
        workspace_id: UUID,
        status: str,
    ) -> None:
        await connection.execute(
            text(
                """
                UPDATE public.files
                SET status = :status
                WHERE id = :file_id AND workspace_id = :workspace_id
                """
            ),
            {"status": status, "file_id": file_id, "workspace_id": workspace_id},
        )


def ensure_workspace_object_key(*, workspace_id: UUID, file_id: UUID, file_name: str) -> str:
    return workspace_bound_object_key(
        workspace_id=str(workspace_id),
        file_id=str(file_id),
        file_name=file_name,
    )
