from __future__ import annotations

import hashlib
import json
from datetime import UTC, datetime, timedelta
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.building_blocks.settings import Settings, get_settings
from edgemint.files.storage import get_object_storage
from edgemint.workers.errors import worker_error
from edgemint.workers.sessions import resolve_worker_session
from edgemint.workers.transport_recovery import (
    TransportEventKind,
    TransportRecoveryService,
    aggregate_sequence_for_transport,
    transport_event_identity,
)


class AssignmentInputService:
    """Production input manifest and content for leased assignments."""

    settings: Settings = get_settings()
    transport_recovery: TransportRecoveryService = TransportRecoveryService()

    async def _assignment_row(
        self,
        connection: AsyncConnection,
        *,
        access_token: str,
        assignment_id: str,
    ) -> dict[str, Any]:
        from uuid import UUID

        try:
            internal_id = UUID(assignment_id)
        except ValueError as exc:
            raise worker_error("INPUT_SCHEMA_INVALID", detail="assignmentId must be a UUID") from exc

        session = await resolve_worker_session(connection, access_token=access_token)
        row = (
            await connection.execute(
                text(
                    """
                    SELECT
                        assignment.id AS assignment_id,
                        assignment.workspace_id,
                        assignment.status,
                        assignment.lease_expires_at_utc,
                        task.public_id AS task_public_id,
                        task.task_type,
                        revision.inline_text,
                        revision.parameters_json,
                        revision.input_file_id,
                        file.public_id AS input_file_public_id,
                        file.content_type AS input_file_mime,
                        file.size_bytes AS input_file_size,
                        file.sha256 AS input_file_digest,
                        file.object_key AS input_object_key
                    FROM public.assignments AS assignment
                    JOIN public.task_attempts AS attempt
                      ON attempt.id = assignment.task_attempt_id
                     AND attempt.workspace_id = assignment.workspace_id
                    JOIN public.tasks AS task
                      ON task.id = attempt.task_id
                     AND task.workspace_id = attempt.workspace_id
                    JOIN public.task_revisions AS revision
                      ON revision.id = task.current_revision_id
                     AND revision.workspace_id = task.workspace_id
                    LEFT JOIN public.files AS file
                      ON file.id = revision.input_file_id
                     AND file.workspace_id = revision.workspace_id
                    WHERE assignment.id = :assignment_id
                      AND assignment.worker_device_id = :worker_device_id
                    """
                ),
                {"assignment_id": internal_id, "worker_device_id": session.device_id},
            )
        ).mappings().first()
        if row is None:
            raise worker_error("TENANT_RESOURCE_NOT_FOUND", detail="assignment not found")
        if str(row["status"]) not in {"leased", "running", "completed"}:
            raise worker_error("ASSIGNMENT_STALE_FENCE", detail="assignment not active")
        if row["lease_expires_at_utc"] <= datetime.now(UTC):
            raise worker_error("ASSIGNMENT_STALE_FENCE", detail="lease expired")
        return dict(row)

    def _manifest_expires_at(self) -> str:
        return (datetime.now(UTC) + timedelta(seconds=120)).isoformat()

    def _build_prompt(
        self,
        *,
        task_type: str,
        inline_text: str | None,
        parameters: dict[str, Any],
    ) -> str:
        instructions = parameters.get("instructions")
        if isinstance(instructions, str) and instructions.strip():
            base = instructions.strip()
        elif inline_text and inline_text.strip():
            base = inline_text.strip()
        else:
            base = f"Process {task_type} task"
        return base[:32_000]

    async def input_manifest(
        self,
        connection: AsyncConnection,
        *,
        access_token: str,
        assignment_id: str,
        task_type_hint: str | None = None,
    ) -> dict[str, Any]:
        row = await self._assignment_row(
            connection,
            access_token=access_token,
            assignment_id=assignment_id,
        )
        task_type = str(row["task_type"])
        if task_type_hint and task_type_hint != task_type:
            raise worker_error("INPUT_SCHEMA_INVALID", detail="taskType mismatch")

        parameters = row["parameters_json"]
        if isinstance(parameters, str):
            parameters = json.loads(parameters)
        if not isinstance(parameters, dict):
            parameters = {}

        api_base = self.settings.worker_api_public_base_url.rstrip("/")
        manifest: dict[str, Any] = {
            "taskId": str(row["task_public_id"]),
            "taskType": task_type,
            "prompt": self._build_prompt(
                task_type=task_type,
                inline_text=row["inline_text"],
                parameters=parameters,
            ),
            "expiresAt": self._manifest_expires_at(),
        }
        if row["inline_text"]:
            manifest["inputText"] = str(row["inline_text"])[:32_000]
        flex_data = parameters.get("inputData")
        if isinstance(flex_data, dict):
            manifest["inputData"] = flex_data
        if row["input_file_id"] is not None:
            manifest["inputContentUrl"] = (
                f"{api_base}/assignments/{assignment_id}/input/content"
            )
            manifest["inputFile"] = {
                "fileId": str(row["input_file_public_id"]),
                "mimeType": row["input_file_mime"],
                "sizeBytes": int(row["input_file_size"] or 0),
                "digestSha256": row["input_file_digest"],
            }
        return manifest

    async def input_content(
        self,
        connection: AsyncConnection,
        *,
        access_token: str,
        assignment_id: str,
    ) -> tuple[bytes, str, str]:
        row = await self._assignment_row(
            connection,
            access_token=access_token,
            assignment_id=assignment_id,
        )
        if row["input_file_id"] is None:
            raise worker_error("TENANT_RESOURCE_NOT_FOUND", detail="input file not found")
        object_key = row.get("input_object_key")
        if not object_key:
            raise worker_error("TENANT_RESOURCE_NOT_FOUND", detail="input content missing")
        storage = get_object_storage(self.settings)
        head = await storage.head_object(object_key=str(object_key))
        if head is None:
            raise worker_error("TENANT_RESOURCE_NOT_FOUND", detail="input blob missing")
        get_payload = getattr(storage, "get_object", None)
        if get_payload is None:
            raise worker_error("STORAGE_UNAVAILABLE", detail="object read not supported")
        payload = await get_payload(object_key=str(object_key))
        if payload is None:
            raise worker_error("TENANT_RESOURCE_NOT_FOUND", detail="input blob missing")
        mime = str(row["input_file_mime"] or "application/octet-stream")
        file_name = str(row["input_file_public_id"] or "input")
        return payload, mime, file_name

    async def record_output(
        self,
        connection: AsyncConnection,
        *,
        access_token: str,
        assignment_id: str,
        result_text: str,
        metrics: dict[str, Any] | None = None,
        result_file_bytes: bytes | None = None,
        result_file_name: str | None = None,
        result_mime_type: str | None = None,
    ) -> dict[str, Any]:
        row = await self._assignment_row(
            connection,
            access_token=access_token,
            assignment_id=assignment_id,
        )
        from uuid import UUID

        internal_id = UUID(assignment_id)
        digest_source = result_text.encode("utf-8")
        if result_file_bytes is not None:
            digest_source = digest_source + result_file_bytes
        result_sha256 = hashlib.sha256(digest_source).hexdigest()
        payload: dict[str, Any] = {
            "assignmentId": assignment_id,
            "resultText": result_text,
            "metrics": metrics or {},
            "recordedAt": datetime.now(UTC).isoformat(),
            "resultSha256": result_sha256,
        }
        if result_file_bytes is not None:
            payload["hasResultFile"] = True
            payload["resultFileName"] = result_file_name or "result.bin"
            payload["resultMimeType"] = result_mime_type or "application/octet-stream"
            payload["resultFileSizeBytes"] = len(result_file_bytes)
        fence_row = (
            await connection.execute(
                text("SELECT fence_token FROM public.assignments WHERE id = :id"),
                {"id": internal_id},
            )
        ).mappings().first()
        fence_token = int(fence_row["fence_token"]) if fence_row else 1
        await self.transport_recovery.record(
            connection,
            workspace_id=row["workspace_id"],
            assignment_id=internal_id,
            event_kind=TransportEventKind.RESULT,
            event_identity=transport_event_identity(
                assignment_id=assignment_id,
                fence_token=fence_token,
                event_kind=TransportEventKind.RESULT,
                result_sha256=result_sha256,
            ),
            payload=payload,
            aggregate_sequence=aggregate_sequence_for_transport(
                fence_token=fence_token,
                event_kind=TransportEventKind.RESULT,
                sequence=0,
            ),
        )
        return {
            "assignmentId": assignment_id,
            "taskId": str(row["task_public_id"]),
            "status": "accepted",
            "hasResultFile": bool(result_file_bytes),
            "resultSha256": result_sha256,
        }
