from __future__ import annotations

from dataclasses import dataclass, field
import base64
import hashlib
import hmac
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.building_blocks.settings import Settings, get_settings
from edgemint.building_blocks.eventing.transactional_outbox import OutboxEvent, enqueue_outbox_event
from edgemint.building_blocks.ids import public_id
from edgemint.security.lease_credentials import LeaseCredentialCipher
from edgemint.security.tokens import hash_session_token
from edgemint.workers.errors import worker_error
from edgemint.workers.sessions import resolve_worker_session


@dataclass(slots=True)
class AssignmentCredentialBootstrapService:
    """Return an existing automatic lease only to its attested target device."""

    settings: Settings = field(default_factory=get_settings)

    async def next_assignment(
        self,
        connection: AsyncConnection,
        *,
        access_token: str,
    ) -> dict[str, Any] | None:
        session = await resolve_worker_session(connection, access_token=access_token)
        if session.device_status != "active":
            raise worker_error("WORKER_NOT_READY", detail="device is not active")
        if (
            session.attestation_status != "verified"
            or session.attestation_expires_at <= datetime.now(UTC)
        ):
            raise worker_error("ATTESTATION_INVALID")

        row = (
            await connection.execute(
                text(
                    """
                    SELECT
                        assignment.id AS assignment_id,
                        assignment.fence_token,
                        assignment.lease_token_hash,
                        credential.lease_token_ciphertext,
                        assignment.lease_expires_at_utc,
                        assignment.start_deadline_at_utc,
                        attempt.id AS attempt_id,
                        revision.id AS revision_id,
                        task.public_id AS task_public_id,
                        task.task_type,
                        revision.model_version_id
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
                    JOIN public.assignment_lease_credentials AS credential
                      ON credential.assignment_id = assignment.id
                     AND credential.worker_device_id = assignment.worker_device_id
                    WHERE assignment.worker_device_id = :worker_device_id
                      AND assignment.status = 'leased'
                      AND assignment.lease_expires_at_utc > CURRENT_TIMESTAMP
                      AND assignment.start_deadline_at_utc > CURRENT_TIMESTAMP
                    ORDER BY assignment.assigned_at_utc, assignment.id
                    FOR UPDATE OF assignment
                    LIMIT 1
                    """
                ),
                {"worker_device_id": session.device_id},
            )
        ).mappings().first()
        if row is None:
            return None

        encrypted = bytes(row["lease_token_ciphertext"])
        try:
            lease_token = LeaseCredentialCipher.from_settings(self.settings).decrypt(
                encrypted,
                worker_device_id=session.device_id,
            )
        except RuntimeError as exc:
            raise worker_error(
                "LEASE_CREDENTIAL_UNAVAILABLE",
                detail="lease credential could not be recovered",
            ) from exc
        if hash_session_token(lease_token) != bytes(row["lease_token_hash"]):
            raise worker_error(
                "LEASE_CREDENTIAL_UNAVAILABLE",
                detail="lease credential integrity check failed",
            )

        assignment_id = str(row["assignment_id"])
        api_base = self.settings.worker_api_public_base_url.rstrip("/")
        model_version_id = row["model_version_id"]
        return {
            "assignmentId": assignment_id,
            "attemptId": str(row["attempt_id"]),
            "revisionId": str(row["revision_id"]),
            "taskId": str(row["task_public_id"]),
            "leaseToken": lease_token,
            "fenceToken": int(row["fence_token"]),
            "leaseExpiresAt": row["lease_expires_at_utc"].isoformat(),
            "taskType": str(row["task_type"]),
            "modelVersionId": str(model_version_id) if model_version_id else "builtin",
            "inputManifestUrl": f"{api_base}/assignments/{assignment_id}/input-manifest",
            "outputUploadUrl": f"{api_base}/assignments/{assignment_id}/output",
            "assignmentMode": "auto",
            "executionStartsAutomatically": True,
            "startDeadlineAt": row["start_deadline_at_utc"].isoformat(),
        }


@dataclass(slots=True)
class AssignmentCommandService:
    settings: Settings = field(default_factory=get_settings)

    @staticmethod
    def _assignment_uuid(value: str) -> Any:
        from uuid import UUID

        try:
            return UUID(value)
        except ValueError as exc:
            raise worker_error("INPUT_SCHEMA_INVALID", detail="assignmentId must be a UUID") from exc

    @staticmethod
    def _receipt(operation: str) -> dict[str, Any]:
        return {
            "operationId": public_id("op"),
            "accepted": True,
            "status": "accepted",
            "operation": operation,
            "occurredAt": datetime.now(UTC).isoformat(),
        }

    async def start(
        self,
        connection: AsyncConnection,
        *,
        access_token: str,
        assignment_id: str,
        lease_token: str,
        fence_token: int,
    ) -> dict[str, Any]:
        session = await resolve_worker_session(connection, access_token=access_token)
        internal_id = self._assignment_uuid(assignment_id)
        row = (
            await connection.execute(
                text(
                    """
                    SELECT status, workspace_id, fence_token, lease_token_hash,
                           lease_expires_at_utc, start_deadline_at_utc
                    FROM public.assignments
                    WHERE id = :assignment_id AND worker_device_id = :worker_device_id
                    FOR UPDATE
                    """
                ),
                {"assignment_id": internal_id, "worker_device_id": session.device_id},
            )
        ).mappings().first()
        if row is None:
            raise worker_error("TENANT_RESOURCE_NOT_FOUND", detail="assignment not found")
        self._verify_active_credential(row, lease_token=lease_token, fence_token=fence_token)
        if str(row["status"]) == "running":
            return self._receipt("reportAssignmentStartedReplay")
        if str(row["status"]) != "leased":
            raise worker_error("ASSIGNMENT_STALE_FENCE")

        heartbeat_sequence = (
            await connection.execute(
                text(
                    """
                    SELECT sequence_number
                    FROM public.worker_heartbeats
                    WHERE worker_device_id = :worker_device_id
                    ORDER BY received_at_utc DESC, sequence_number DESC
                    LIMIT 1
                    """
                ),
                {"worker_device_id": session.device_id},
            )
        ).scalar_one_or_none()
        if heartbeat_sequence is None:
            raise worker_error("WORKER_NOT_READY", detail="heartbeat required before start")

        await connection.execute(
            text(
                """
                SELECT public.start_auto_assigned_work(
                    :assignment_id, :worker_device_id, :fence_token,
                    :lease_token_hash, :start_sequence, :health_snapshot_sequence
                )
                """
            ),
            {
                "assignment_id": internal_id,
                "worker_device_id": session.device_id,
                "fence_token": fence_token,
                "lease_token_hash": hash_session_token(lease_token),
                "start_sequence": 1,
                "health_snapshot_sequence": int(heartbeat_sequence),
            },
        )
        await enqueue_outbox_event(
            connection,
            OutboxEvent(
                event_type="assignment.started",
                aggregate_type="assignment",
                aggregate_id=assignment_id,
                aggregate_sequence=fence_token * 1_000_000_000 + 1,
                workspace_id=row["workspace_id"],
                cloud_event=self._cloud_event(
                    event_type="io.edgemint.assignment.started.v1",
                    assignment_id=assignment_id,
                    data={
                        "assignmentId": assignment_id,
                        "workerDeviceId": str(session.device_id),
                        "fenceToken": fence_token,
                        "healthSnapshotSequence": int(heartbeat_sequence),
                    },
                ),
            ),
        )
        return self._receipt("reportAssignmentStarted")

    async def renew(
        self,
        connection: AsyncConnection,
        *,
        access_token: str,
        assignment_id: str,
        lease_token: str,
        fence_token: int,
        sequence: int,
    ) -> dict[str, Any]:
        session = await resolve_worker_session(connection, access_token=access_token)
        internal_id = self._assignment_uuid(assignment_id)
        row = (
            await connection.execute(
                text(
                    """
                    SELECT status, workspace_id, fence_token, lease_token_hash,
                           lease_expires_at_utc, start_deadline_at_utc
                    FROM public.assignments
                    WHERE id = :assignment_id AND worker_device_id = :worker_device_id
                    FOR UPDATE
                    """
                ),
                {"assignment_id": internal_id, "worker_device_id": session.device_id},
            )
        ).mappings().first()
        if row is None:
            raise worker_error("TENANT_RESOURCE_NOT_FOUND", detail="assignment not found")
        self._verify_active_credential(row, lease_token=lease_token, fence_token=fence_token)
        if str(row["status"]) != "running":
            raise worker_error("ASSIGNMENT_STALE_FENCE")

        expires_at = (
            await connection.execute(
                text(
                    """
                    SELECT public.renew_auto_assignment_lease(
                        :assignment_id, :worker_device_id, :fence_token,
                        :lease_token_hash, :sequence, :lease_seconds
                    )
                    """
                ),
                {
                    "assignment_id": internal_id,
                    "worker_device_id": session.device_id,
                    "fence_token": fence_token,
                    "lease_token_hash": hash_session_token(lease_token),
                    "sequence": sequence,
                    "lease_seconds": 120,
                },
            )
        ).scalar_one_or_none()
        if expires_at is None:
            raise worker_error("LEASE_RENEWAL_REJECTED")
        await enqueue_outbox_event(
            connection,
            OutboxEvent(
                event_type="assignment.lease_renewed",
                aggregate_type="assignment",
                aggregate_id=assignment_id,
                aggregate_sequence=fence_token * 1_000_000_000 + 1_000_000 + sequence,
                workspace_id=row["workspace_id"],
                cloud_event=self._cloud_event(
                    event_type="io.edgemint.assignment.lease_renewed.v1",
                    assignment_id=assignment_id,
                    data={
                        "assignmentId": assignment_id,
                        "workerDeviceId": str(session.device_id),
                        "fenceToken": fence_token,
                        "sequence": sequence,
                        "leaseExpiresAt": expires_at.isoformat(),
                    },
                ),
            ),
        )
        receipt = self._receipt("renewAssignment")
        receipt["leaseExpiresAt"] = expires_at.isoformat()
        receipt["sequence"] = sequence
        return receipt

    async def complete(
        self,
        connection: AsyncConnection,
        *,
        access_token: str,
        assignment_id: str,
        lease_token: str,
        fence_token: int,
        result_sha256: str,
        output_artifact_id: str,
        output_inline: str,
        signature: str,
        metrics: dict[str, Any],
    ) -> dict[str, Any]:
        session = await resolve_worker_session(connection, access_token=access_token)
        internal_id = self._assignment_uuid(assignment_id)
        row = (
            await connection.execute(
                text(
                    """
                    SELECT assignment.status, assignment.workspace_id,
                           assignment.task_attempt_id, assignment.fence_token,
                           assignment.lease_token_hash, assignment.lease_expires_at_utc,
                           task.id AS task_id
                    FROM public.assignments AS assignment
                    JOIN public.task_attempts AS attempt
                      ON attempt.id = assignment.task_attempt_id
                     AND attempt.workspace_id = assignment.workspace_id
                    JOIN public.tasks AS task
                      ON task.id = attempt.task_id
                     AND task.workspace_id = attempt.workspace_id
                    WHERE assignment.id = :assignment_id
                      AND assignment.worker_device_id = :worker_device_id
                    FOR UPDATE OF assignment
                    """
                ),
                {"assignment_id": internal_id, "worker_device_id": session.device_id},
            )
        ).mappings().first()
        if row is None:
            raise worker_error("TENANT_RESOURCE_NOT_FOUND", detail="assignment not found")

        if str(row["status"]) == "completed":
            existing = (
                await connection.execute(
                    text("SELECT result_sha256 FROM public.results WHERE assignment_id = :id"),
                    {"id": internal_id},
                )
            ).scalar_one_or_none()
            if existing == result_sha256:
                return self._receipt("completeAssignmentReplay")
            raise worker_error("ASSIGNMENT_STALE_FENCE")

        self._verify_active_credential(row, lease_token=lease_token, fence_token=fence_token)
        if str(row["status"]) != "running":
            raise worker_error("ASSIGNMENT_STALE_FENCE")
        if len(output_inline.encode("utf-8")) > 2 * 1024 * 1024:
            raise worker_error("INPUT_SCHEMA_INVALID", detail="inline result exceeds 2 MB")
        actual_digest = hashlib.sha256(output_inline.encode("utf-8")).hexdigest()
        if not hmac.compare_digest(actual_digest, result_sha256):
            raise worker_error("INPUT_SCHEMA_INVALID", detail="resultSha256 mismatch")
        signed_payload = f"{assignment_id}|{fence_token}|{result_sha256}|{output_artifact_id}"
        expected_signature = base64.b64encode(
            hmac.new(
                lease_token.encode("utf-8"),
                signed_payload.encode("utf-8"),
                hashlib.sha256,
            ).digest()
        ).decode("ascii")
        if not hmac.compare_digest(signature, expected_signature):
            raise worker_error("INPUT_SCHEMA_INVALID", detail="result signature invalid")

        await connection.execute(
            text(
                """
                INSERT INTO public.results(
                    workspace_id, task_attempt_id, assignment_id, inline_output,
                    result_sha256, worker_signature, status
                ) VALUES (
                    :workspace_id, :attempt_id, :assignment_id, :inline_output,
                    :result_sha256, :worker_signature, 'pending_verification'
                )
                """
            ),
            {
                "workspace_id": row["workspace_id"],
                "attempt_id": row["task_attempt_id"],
                "assignment_id": internal_id,
                "inline_output": output_inline,
                "result_sha256": result_sha256,
                "worker_signature": base64.b64decode(signature, validate=True),
            },
        )
        mutation_params = {
            "assignment_id": internal_id,
            "attempt_id": row["task_attempt_id"],
            "task_id": row["task_id"],
            "workspace_id": row["workspace_id"],
        }
        await connection.execute(
            text("UPDATE public.assignments SET status = 'completed', ended_at_utc = CURRENT_TIMESTAMP WHERE id = :assignment_id"),
            mutation_params,
        )
        await connection.execute(
            text("UPDATE public.task_attempts SET status = 'completed', completed_at_utc = CURRENT_TIMESTAMP WHERE id = :attempt_id AND workspace_id = :workspace_id"),
            mutation_params,
        )
        await connection.execute(
            text("UPDATE public.tasks SET lifecycle_status = 'completed', updated_at_utc = CURRENT_TIMESTAMP WHERE id = :task_id AND workspace_id = :workspace_id"),
            mutation_params,
        )
        await connection.execute(
            text("DELETE FROM public.assignment_lease_credentials WHERE assignment_id = :assignment_id"),
            mutation_params,
        )
        await enqueue_outbox_event(
            connection,
            OutboxEvent(
                event_type="assignment.completed",
                aggregate_type="assignment",
                aggregate_id=assignment_id,
                aggregate_sequence=fence_token * 1_000_000_000 + 900_000_000,
                workspace_id=row["workspace_id"],
                cloud_event=self._cloud_event(
                    event_type="io.edgemint.assignment.completed.v1",
                    assignment_id=assignment_id,
                    data={
                        "assignmentId": assignment_id,
                        "workerDeviceId": str(session.device_id),
                        "fenceToken": fence_token,
                        "resultSha256": result_sha256,
                        "metrics": metrics,
                    },
                ),
            ),
        )
        return self._receipt("completeAssignment")

    @staticmethod
    def _verify_active_credential(
        row: Any,
        *,
        lease_token: str,
        fence_token: int,
    ) -> None:
        if int(row["fence_token"]) != fence_token:
            raise worker_error("ASSIGNMENT_STALE_FENCE")
        if bytes(row["lease_token_hash"]) != hash_session_token(lease_token):
            raise worker_error("LEASE_TOKEN_MISMATCH")
        if row["lease_expires_at_utc"] <= datetime.now(UTC):
            raise worker_error("ASSIGNMENT_STALE_FENCE", detail="lease expired")

    @staticmethod
    def _cloud_event(
        *,
        event_type: str,
        assignment_id: str,
        data: dict[str, Any],
    ) -> dict[str, Any]:
        now = datetime.now(UTC)
        return {
            "specversion": "1.0",
            "id": public_id("event"),
            "source": "urn:edgemint:worker-registry",
            "type": event_type,
            "subject": assignment_id,
            "time": now.isoformat(),
            "datacontenttype": "application/json",
            "data": data,
        }
