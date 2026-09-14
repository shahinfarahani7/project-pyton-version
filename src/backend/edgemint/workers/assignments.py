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
from edgemint.routing.execution_allocation import ExecutionAllocationService
from edgemint.routing.resource_reservations import ResourceReservationService
from edgemint.workers.errors import worker_error
from edgemint.workers.checkpoint_resume import (
    CheckpointManifestSpec,
    CheckpointResumeService,
    DEFAULT_RUNTIME_BACKEND,
)
from edgemint.workers.assignment_delivery_inbox import AssignmentDeliveryInboxService
from edgemint.workers.calibration_feedback import apply_execution_cost_feedback_to_calibration
from edgemint.workers.execution_cost_feedback import (
    ExecutionCostFeedbackService,
    parse_execution_cost_feedback,
)
from edgemint.workers.failure_codes import validate_worker_failure_submission
from edgemint.workers.sessions import resolve_worker_session
from edgemint.results.result_acceptance import ResultAcceptanceService
from edgemint.results.validator import validate_task_result
from edgemint.routing.checkpoint_policy_matrix import get_checkpoint_policy_matrix
from edgemint.tasks.task_run import TaskRunService, TaskRunStatus, TERMINAL_STATUSES
from edgemint.workers.transport_recovery import (
    TransportEventKind,
    TransportRecoveryService,
    aggregate_sequence_for_transport,
    transport_event_identity,
)


@dataclass(slots=True)
class AssignmentCredentialBootstrapService:
    """Return an existing automatic lease only to its attested target device."""

    settings: Settings = field(default_factory=get_settings)
    delivery_inbox: AssignmentDeliveryInboxService = field(default_factory=AssignmentDeliveryInboxService)
    execution_allocations: ExecutionAllocationService = field(default_factory=ExecutionAllocationService)

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
                        assignment.workspace_id,
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
        delivery_id = await self.delivery_inbox.record_poll_delivery(
            connection,
            workspace_id=row["workspace_id"],
            assignment_id=row["assignment_id"],
            worker_device_id=session.device_id,
            fence_token=int(row["fence_token"]),
        )
        api_base = self.settings.worker_api_public_base_url.rstrip("/")
        model_version_id = row["model_version_id"]
        payload: dict[str, Any] = {
            "assignmentId": assignment_id,
            "deliveryInboxId": str(delivery_id),
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
        grant = await self.execution_allocations.load_bootstrap_grant_for_attempt(
            connection,
            task_attempt_id=row["attempt_id"],
        )
        if grant is not None:
            payload["executionPlan"] = grant["executionPlan"]
            payload["allocation"] = grant["allocation"]
        return payload

    async def inbox_bootstrap(
        self,
        connection: AsyncConnection,
        *,
        access_token: str,
    ) -> dict[str, Any]:
        session = await resolve_worker_session(connection, access_token=access_token)
        records = await self.delivery_inbox.bootstrap_for_device(
            connection,
            worker_device_id=session.device_id,
        )
        return {
            "workerDeviceId": str(session.device_id),
            "deliveries": [
                {
                    "deliveryInboxId": str(record.delivery_id),
                    "assignmentId": str(record.assignment_id),
                    "fenceToken": record.fence_token,
                    "deliveryChannel": record.delivery_channel,
                    "acked": record.acked,
                }
                for record in records
            ],
        }


@dataclass(slots=True)
class AssignmentCommandService:
    """Worker assignment lifecycle commands with resource reservation hooks."""

    settings: Settings = field(default_factory=get_settings)
    resource_reservations: ResourceReservationService = field(default_factory=ResourceReservationService)
    execution_cost_feedback: ExecutionCostFeedbackService = field(default_factory=ExecutionCostFeedbackService)
    task_runs: TaskRunService = field(default_factory=TaskRunService)
    result_acceptance: ResultAcceptanceService = field(default_factory=ResultAcceptanceService)
    transport_recovery: TransportRecoveryService = field(default_factory=TransportRecoveryService)
    checkpoint_resume: CheckpointResumeService = field(default_factory=CheckpointResumeService)
    delivery_inbox: AssignmentDeliveryInboxService = field(default_factory=AssignmentDeliveryInboxService)

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

    async def _win_task_run_terminal(
        self,
        connection: AsyncConnection,
        *,
        task_run_id: Any,
        terminal_status: TaskRunStatus,
        terminal_outcome: str,
    ) -> None:
        if task_run_id is None:
            return
        from uuid import UUID

        run_id = UUID(str(task_run_id))
        commit = await self.task_runs.commit_terminal(
            connection,
            task_run_id=run_id,
            terminal_status=terminal_status,
            terminal_outcome=terminal_outcome,
        )
        if commit.committed:
            return
        existing = await self.task_runs.get_status(connection, task_run_id=run_id)
        if existing in TERMINAL_STATUSES:
            raise worker_error(
                "ASSIGNMENT_STALE_FENCE",
                detail=f"task run already terminal: {existing}",
            )
        raise worker_error(
            "ASSIGNMENT_STALE_FENCE",
            detail="task run terminal commit lost race",
        )

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

        await self.delivery_inbox.acknowledge_delivery(
            connection,
            assignment_id=internal_id,
            worker_device_id=session.device_id,
            fence_token=fence_token,
            ack_sequence=1,
        )

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
        if self.settings.worker_resource_reservations_enabled:
            await self.resource_reservations.activate_for_assignment(
                connection,
                assignment_id=internal_id,
                fence_token=fence_token,
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

    async def progress(
        self,
        connection: AsyncConnection,
        *,
        access_token: str,
        assignment_id: str,
        lease_token: str,
        fence_token: int,
        sequence: int,
        stage: str,
        progress_bps: int,
        metrics: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        session = await resolve_worker_session(connection, access_token=access_token)
        internal_id = self._assignment_uuid(assignment_id)
        row = (
            await connection.execute(
                text(
                    """
                    SELECT status, workspace_id, fence_token, lease_token_hash,
                           lease_expires_at_utc
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
        if sequence < 1:
            raise worker_error("INPUT_SCHEMA_INVALID", detail="sequence must be >= 1")
        if not 0 <= progress_bps <= 10_000:
            raise worker_error("INPUT_SCHEMA_INVALID", detail="progressBps out of range")

        progress_data: dict[str, Any] = {
            "assignmentId": assignment_id,
            "workerDeviceId": str(session.device_id),
            "fenceToken": fence_token,
            "sequence": sequence,
            "stage": stage,
            "progressBps": progress_bps,
        }
        if metrics is not None:
            progress_data["metrics"] = metrics

        transport = await self.transport_recovery.record(
            connection,
            workspace_id=row["workspace_id"],
            assignment_id=internal_id,
            event_kind=TransportEventKind.PROGRESS,
            event_identity=transport_event_identity(
                assignment_id=assignment_id,
                fence_token=fence_token,
                event_kind=TransportEventKind.PROGRESS,
                sequence=sequence,
            ),
            payload=progress_data,
            aggregate_sequence=aggregate_sequence_for_transport(
                fence_token=fence_token,
                event_kind=TransportEventKind.PROGRESS,
                sequence=sequence,
            ),
        )
        if not transport.is_new:
            receipt = self._receipt("progressAssignmentReplay")
            receipt["sequence"] = sequence
            receipt["progressBps"] = progress_bps
            return receipt

        await enqueue_outbox_event(
            connection,
            OutboxEvent(
                event_type="task_progress",
                aggregate_type="assignment",
                aggregate_id=assignment_id,
                aggregate_sequence=transport.aggregate_sequence,
                workspace_id=row["workspace_id"],
                cloud_event=self._cloud_event(
                    event_type="io.edgemint.task.progress.v1",
                    assignment_id=assignment_id,
                    data=progress_data,
                ),
            ),
        )
        receipt = self._receipt("progressAssignment")
        receipt["sequence"] = sequence
        receipt["progressBps"] = progress_bps
        return receipt

    async def checkpoint(
        self,
        connection: AsyncConnection,
        *,
        access_token: str,
        assignment_id: str,
        lease_token: str,
        fence_token: int,
        sequence: int,
        model_version_id: str,
        input_sha256: str,
        checkpoint_sha256: str,
        encrypted_blob_ref: str,
        chunk_index: int | None = None,
    ) -> dict[str, Any]:
        session = await resolve_worker_session(connection, access_token=access_token)
        internal_id = self._assignment_uuid(assignment_id)
        row = (
            await connection.execute(
                text(
                    """
                    SELECT assignment.status, assignment.workspace_id, assignment.fence_token,
                           assignment.lease_token_hash, assignment.lease_expires_at_utc,
                           assignment.id AS assignment_internal_id,
                           attempt.id AS task_attempt_id,
                           attempt.task_run_id AS task_run_id,
                           task.task_revision_id AS task_revision_id,
                           task.task_type AS task_type
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
        if not get_checkpoint_policy_matrix().checkpoint_enabled_for(str(row["task_type"])):
            raise worker_error("CHECKPOINT_NOT_SUPPORTED", detail="task type does not support checkpoint")
        self._verify_active_credential(row, lease_token=lease_token, fence_token=fence_token)
        if str(row["status"]) != "running":
            raise worker_error("ASSIGNMENT_STALE_FENCE")
        if sequence < 1:
            raise worker_error("INPUT_SCHEMA_INVALID", detail="sequence must be >= 1")
        if len(input_sha256) != 64 or len(checkpoint_sha256) != 64:
            raise worker_error("INPUT_SCHEMA_INVALID", detail="checkpoint digest must be sha256 hex")
        if not encrypted_blob_ref.strip():
            raise worker_error("INPUT_SCHEMA_INVALID", detail="encryptedBlobRef is required")

        checkpoint_data: dict[str, Any] = {
            "assignmentId": assignment_id,
            "workerDeviceId": str(session.device_id),
            "fenceToken": fence_token,
            "sequence": sequence,
            "modelVersionId": model_version_id,
            "inputSha256": input_sha256,
            "checkpointSha256": checkpoint_sha256,
            "encryptedBlobRef": encrypted_blob_ref,
        }
        if chunk_index is not None:
            checkpoint_data["chunkIndex"] = chunk_index

        transport = await self.transport_recovery.record(
            connection,
            workspace_id=row["workspace_id"],
            assignment_id=internal_id,
            event_kind=TransportEventKind.CHECKPOINT,
            event_identity=transport_event_identity(
                assignment_id=assignment_id,
                fence_token=fence_token,
                event_kind=TransportEventKind.CHECKPOINT,
                sequence=sequence,
            ),
            payload=checkpoint_data,
            aggregate_sequence=aggregate_sequence_for_transport(
                fence_token=fence_token,
                event_kind=TransportEventKind.CHECKPOINT,
                sequence=sequence,
            ),
        )
        if not transport.is_new:
            receipt = self._receipt("checkpointAssignmentReplay")
            receipt["sequence"] = sequence
            return receipt

        await enqueue_outbox_event(
            connection,
            OutboxEvent(
                event_type="task_checkpoint_saved",
                aggregate_type="assignment",
                aggregate_id=assignment_id,
                aggregate_sequence=transport.aggregate_sequence,
                workspace_id=row["workspace_id"],
                cloud_event=self._cloud_event(
                    event_type="io.edgemint.task.checkpoint.saved.v1",
                    assignment_id=assignment_id,
                    data=checkpoint_data,
                ),
            ),
        )
        if chunk_index is not None and row.get("task_run_id") is not None:
            from edgemint.routing.execution_plan_resolver import resolve_execution_plan

            plan = resolve_execution_plan(task_type=str(row["task_type"]))
            chunk_id = f"chunk-{chunk_index}"
            await self.checkpoint_resume.publish_manifest(
                connection,
                CheckpointManifestSpec(
                    workspace_id=row["workspace_id"],
                    task_run_id=row["task_run_id"],
                    task_revision_id=row["task_revision_id"],
                    task_attempt_id=row["task_attempt_id"],
                    assignment_id=internal_id,
                    input_digest=input_sha256,
                    execution_plan_id=plan.plan_name,
                    execution_plan_version=plan.plan_version,
                    stage_id="llm-map",
                    chunk_id=chunk_id,
                    chunk_index=chunk_index,
                    model_version_id=model_version_id,
                    artifact_digest=model_version_id,
                    runtime_version=DEFAULT_RUNTIME_BACKEND,
                    prompt_template_version="1.0",
                    producer_attempt_id=row["task_attempt_id"],
                    producer_assignment_id=internal_id,
                    producer_fence_token=fence_token,
                    producer_worker_device_id=session.device_id,
                    processed_ranges={"chunkIndex": chunk_index},
                    completed_chunk_ids=[chunk_id],
                    result_artifact_hash=checkpoint_sha256,
                ),
            )
        receipt = self._receipt("checkpointAssignment")
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
                           assignment.worker_device_id,
                           task.id AS task_id,
                           task.task_type AS task_type,
                           attempt.task_run_id AS task_run_id,
                           COALESCE(run.generation, 1) AS task_run_generation
                    FROM public.assignments AS assignment
                    JOIN public.task_attempts AS attempt
                      ON attempt.id = assignment.task_attempt_id
                     AND attempt.workspace_id = assignment.workspace_id
                    JOIN public.tasks AS task
                      ON task.id = attempt.task_id
                     AND task.workspace_id = attempt.workspace_id
                    LEFT JOIN public.task_runs AS run
                      ON run.id = attempt.task_run_id
                     AND run.workspace_id = attempt.workspace_id
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

        task_input_row = (
            await connection.execute(
                text(
                    """
                    SELECT revision.inline_text, revision.parameters_json
                    FROM public.task_attempts AS attempt
                    JOIN public.tasks AS task
                      ON task.id = attempt.task_id
                     AND task.workspace_id = attempt.workspace_id
                    JOIN public.task_revisions AS revision
                      ON revision.id = task.current_revision_id
                     AND revision.workspace_id = task.workspace_id
                    WHERE attempt.id = :attempt_id
                      AND attempt.workspace_id = :workspace_id
                    """
                ),
                {"attempt_id": row["task_attempt_id"], "workspace_id": row["workspace_id"]},
            )
        ).mappings().first()
        task_input: dict[str, Any] | None = None
        if task_input_row is not None:
            params = task_input_row["parameters_json"]
            task_input = {
                "inlineText": task_input_row["inline_text"],
                "parameters": params if isinstance(params, dict) else {},
            }
        validation = validate_task_result(
            task_type=str(row["task_type"]),
            inline_output=output_inline,
            task_input=task_input,
        )
        if not validation.valid:
            raise worker_error(
                validation.failure_code or "RESULT_SCHEMA_INVALID",
                detail=validation.detail,
            )
        terminal_status = TaskRunStatus.SUCCEEDED
        terminal_outcome = "assignment_complete"
        if validation.worker_status == "partial":
            terminal_status = TaskRunStatus.SUCCEEDED
            terminal_outcome = "assignment_partial"
        elif validation.worker_status == "failed":
            raise worker_error("RESULT_WORKER_FAILED", detail=validation.detail)

        task_run_id = row["task_run_id"]
        candidate_id = None
        if task_run_id is not None:
            pinned = await self.result_acceptance.pin_candidate(
                connection,
                workspace_id=row["workspace_id"],
                task_run_id=task_run_id,
                task_attempt_id=row["task_attempt_id"],
                assignment_id=internal_id,
                generation=int(row["task_run_generation"]),
                result_sha256=result_sha256,
                worker_device_id=row["worker_device_id"],
                fence_token=fence_token,
            )
            candidate_id = pinned.candidate_id
            await self.result_acceptance.record_validation(
                connection,
                workspace_id=row["workspace_id"],
                candidate_id=candidate_id,
                passed=True,
            )
            try:
                await self.result_acceptance.accept_outcome(
                    connection,
                    workspace_id=row["workspace_id"],
                    task_run_id=task_run_id,
                    candidate_id=candidate_id,
                    worker_device_id=row["worker_device_id"],
                    terminal_status=terminal_status,
                    terminal_outcome=terminal_outcome,
                )
            except Exception as exc:
                from edgemint.results.errors import ResultServiceError

                if isinstance(exc, ResultServiceError) and exc.code == "RESULT_TERMINAL_LOST":
                    raise worker_error("ASSIGNMENT_STALE_FENCE", detail="terminal race lost") from exc
                raise
        else:
            await self._win_task_run_terminal(
                connection,
                task_run_id=task_run_id,
                terminal_status=TaskRunStatus.SUCCEEDED,
                terminal_outcome="assignment_complete",
            )

        await connection.execute(
            text(
                """
                INSERT INTO public.results(
                    workspace_id, task_attempt_id, assignment_id, inline_output,
                    result_sha256, worker_signature, status, result_candidate_id
                ) VALUES (
                    :workspace_id, :attempt_id, :assignment_id, :inline_output,
                    :result_sha256, :worker_signature, 'pending_verification', :candidate_id
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
                "candidate_id": candidate_id,
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
        if self.settings.worker_resource_reservations_enabled:
            await self.resource_reservations.release_for_assignment(
                connection,
                assignment_id=internal_id,
                fence_token=fence_token,
                stop_reason="assignment_complete",
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
        cost_feedback_raw = metrics.get("costFeedback")
        if cost_feedback_raw is not None:
            feedback = parse_execution_cost_feedback(cost_feedback_raw)
            await self.execution_cost_feedback.persist_for_assignment(
                connection,
                workspace_id=row["workspace_id"],
                assignment_id=internal_id,
                task_attempt_id=row["task_attempt_id"],
                worker_device_id=session.device_id,
                fence_token=fence_token,
                task_type=str(row["task_type"]),
                payload=feedback,
            )
            await apply_execution_cost_feedback_to_calibration(
                connection,
                worker_device_id=session.device_id,
                payload=feedback,
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

    async def fail(
        self,
        connection: AsyncConnection,
        *,
        access_token: str,
        assignment_id: str,
        lease_token: str,
        fence_token: int,
        error_code: str,
        retryable: bool,
        diagnostics: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        validate_worker_failure_submission(error_code=error_code, retryable=retryable)
        session = await resolve_worker_session(connection, access_token=access_token)
        internal_id = self._assignment_uuid(assignment_id)
        row = (
            await connection.execute(
                text(
                    """
                    SELECT assignment.status, assignment.workspace_id,
                           assignment.task_attempt_id, assignment.fence_token,
                           assignment.lease_token_hash, assignment.lease_expires_at_utc,
                           assignment.failure_reason_code,
                           task.id AS task_id,
                           task.public_id AS task_public_id,
                           attempt.task_run_id AS task_run_id
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

        if str(row["status"]) == "failed":
            if str(row["failure_reason_code"] or "") == error_code:
                return self._receipt("failAssignmentReplay")
            raise worker_error("ASSIGNMENT_STALE_FENCE")

        self._verify_active_credential(row, lease_token=lease_token, fence_token=fence_token)
        if str(row["status"]) not in {"running", "leased"}:
            raise worker_error("ASSIGNMENT_STALE_FENCE")

        failure_data: dict[str, Any] = {
            "assignmentId": assignment_id,
            "attemptId": str(row["task_attempt_id"]),
            "workerDeviceId": str(session.device_id),
            "fenceToken": fence_token,
            "failureCode": error_code,
            "retryable": retryable,
            "observedAt": datetime.now(UTC).isoformat(),
        }
        if diagnostics:
            failure_data["diagnostics"] = diagnostics

        if not retryable:
            await self._win_task_run_terminal(
                connection,
                task_run_id=row["task_run_id"],
                terminal_status=TaskRunStatus.FAILED,
                terminal_outcome=error_code,
            )

        mutation_params = {
            "assignment_id": internal_id,
            "attempt_id": row["task_attempt_id"],
            "task_id": row["task_id"],
            "workspace_id": row["workspace_id"],
            "failure_reason_code": error_code,
        }
        await connection.execute(
            text(
                """
                UPDATE public.assignments
                SET status = 'failed',
                    ended_at_utc = CURRENT_TIMESTAMP,
                    failure_reason_code = :failure_reason_code
                WHERE id = :assignment_id
                """
            ),
            mutation_params,
        )
        if self.settings.worker_resource_reservations_enabled:
            await self.resource_reservations.release_for_assignment(
                connection,
                assignment_id=internal_id,
                fence_token=fence_token,
                stop_reason="assignment_fail",
            )
        await connection.execute(
            text(
                """
                UPDATE public.task_attempts
                SET status = 'failed', completed_at_utc = CURRENT_TIMESTAMP
                WHERE id = :attempt_id AND workspace_id = :workspace_id
                """
            ),
            mutation_params,
        )
        await connection.execute(
            text(
                """
                UPDATE public.tasks
                SET lifecycle_status = 'failed', updated_at_utc = CURRENT_TIMESTAMP
                WHERE id = :task_id AND workspace_id = :workspace_id
                """
            ),
            mutation_params,
        )
        await connection.execute(
            text("DELETE FROM public.assignment_lease_credentials WHERE assignment_id = :assignment_id"),
            mutation_params,
        )
        await enqueue_outbox_event(
            connection,
            OutboxEvent(
                event_type="task.failed",
                aggregate_type="assignment",
                aggregate_id=assignment_id,
                aggregate_sequence=fence_token * 1_000_000_000 + 800_000_000,
                workspace_id=row["workspace_id"],
                cloud_event=self._cloud_event(
                    event_type="io.edgemint.task.failed.v1",
                    assignment_id=assignment_id,
                    data={
                        "taskId": str(row["task_public_id"]),
                        "aggregateVersion": 1,
                        "occurredAt": failure_data["observedAt"],
                        "action": "failed",
                        "workspaceId": str(row["workspace_id"]),
                        "reasonCode": error_code,
                        "actorType": "worker",
                        **failure_data,
                    },
                ),
            ),
        )
        receipt = self._receipt("failAssignment")
        receipt["errorCode"] = error_code
        receipt["retryable"] = retryable
        return receipt

    async def confirm_physical_stop(
        self,
        connection: AsyncConnection,
        *,
        access_token: str,
        assignment_id: str,
        lease_token: str,
        fence_token: int,
        proof: str,
        reason: str = "worker_stop_confirmed",
    ) -> dict[str, Any]:
        session = await resolve_worker_session(connection, access_token=access_token)
        internal_id = self._assignment_uuid(assignment_id)
        row = (
            await connection.execute(
                text(
                    """
                    SELECT status, fence_token, lease_token_hash, lease_expires_at_utc
                    FROM public.assignments
                    WHERE id = :assignment_id
                      AND worker_device_id = :worker_device_id
                    FOR UPDATE
                    """
                ),
                {"assignment_id": internal_id, "worker_device_id": session.device_id},
            )
        ).mappings().first()
        if row is None:
            raise worker_error("TENANT_RESOURCE_NOT_FOUND", detail="assignment not found")
        if str(row["status"]) in {"completed", "failed", "abandoned"}:
            if not self.settings.worker_resource_reservations_enabled:
                return self._receipt("confirmPhysicalStopReplay")
            committed = await self.resource_reservations.confirm_physical_stop_for_assignment(
                connection,
                assignment_id=internal_id,
                fence_token=fence_token,
                proof=proof,
                reason=reason,
            )
            receipt = self._receipt("confirmPhysicalStopReplay" if committed else "confirmPhysicalStopStale")
            receipt["physicalReleaseCommitted"] = committed
            return receipt
        self._verify_active_credential(row, lease_token=lease_token, fence_token=fence_token)
        if not self.settings.worker_resource_reservations_enabled:
            return self._receipt("confirmPhysicalStop")
        committed = await self.resource_reservations.confirm_physical_stop_for_assignment(
            connection,
            assignment_id=internal_id,
            fence_token=fence_token,
            proof=proof,
            reason=reason,
        )
        if not committed:
            raise worker_error("ASSIGNMENT_STALE_FENCE", detail="physical release not confirmed")
        receipt = self._receipt("confirmPhysicalStop")
        receipt["physicalReleaseCommitted"] = True
        return receipt

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
