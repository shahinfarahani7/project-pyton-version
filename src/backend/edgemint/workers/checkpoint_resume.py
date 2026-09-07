from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from enum import StrEnum
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.workers.errors import worker_error

CHECKPOINT_SCHEMA_VERSION = "1.0.0"
VALIDATION_VERSION = "checkpoint-v1"
DEFAULT_RETENTION_POLICY_VERSION = "default-v1"
DEFAULT_RUNTIME_BACKEND = "flutter_gemma_mediapipe_v1"
DEFAULT_CHUNKER_VERSION = "semantic-chunk-v1"
DEFAULT_TOKENIZER_VERSION = "conservative-char-v1"


class ResumeGrantStatus(StrEnum):
    ACTIVE = "active"
    CONSUMED = "consumed"
    REVOKED = "revoked"
    EXPIRED = "expired"


class ResumeCompatibilityDecision(StrEnum):
    COMPATIBLE = "compatible"
    INCOMPATIBLE_MODEL_SPACE = "incompatible_model_space"
    INCOMPATIBLE_RUNTIME = "incompatible_runtime"
    INCOMPATIBLE_PROMPT_TEMPLATE = "incompatible_prompt_template"
    INCOMPATIBLE_EXECUTION_PLAN = "incompatible_execution_plan"
    INPUT_DIGEST_MISMATCH = "input_digest_mismatch"
    CHECKPOINT_NOT_ACCEPTED = "checkpoint_not_accepted"
    GRANT_EXPIRED = "grant_expired"
    UNAUTHORIZED_CHUNK = "unauthorized_chunk"


@dataclass(frozen=True, slots=True)
class CheckpointManifestSpec:
    workspace_id: UUID
    task_run_id: UUID
    task_revision_id: UUID
    task_attempt_id: UUID
    assignment_id: UUID
    input_digest: str
    execution_plan_id: str
    execution_plan_version: str
    stage_id: str
    chunk_id: str
    chunk_index: int
    model_version_id: str
    artifact_digest: str
    runtime_version: str
    prompt_template_version: str
    producer_attempt_id: UUID
    producer_assignment_id: UUID
    producer_fence_token: int
    producer_worker_device_id: UUID
    processed_ranges: dict[str, Any]
    completed_chunk_ids: list[str]
    result_artifact_hash: str
    chunker_version: str = DEFAULT_CHUNKER_VERSION
    tokenizer_version: str = DEFAULT_TOKENIZER_VERSION
    producer_worker_boot_id: str | None = None
    backend: str = DEFAULT_RUNTIME_BACKEND


@dataclass(frozen=True, slots=True)
class ResumeGrantSpec:
    workspace_id: UUID
    task_run_id: UUID
    assignment_id: UUID
    fence_token: int
    worker_device_id: UUID
    checkpoint_manifest_id: UUID
    input_digest: str
    authorized_chunk_ids: tuple[str, ...]
    authorized_stage_ids: tuple[str, ...]
    model_version_id: str
    runtime_version: str
    prompt_template_version: str
    execution_plan_version: str
    producer_fence_token: int
    producer_assignment_id: UUID
    expires_at_utc: datetime


@dataclass(frozen=True, slots=True)
class ResumeCompatibilityResult:
    decision: ResumeCompatibilityDecision
    permitted: bool
    detail: str | None = None


def evaluate_resume_compatibility(
    *,
    manifest_model_version_id: str,
    manifest_runtime_version: str,
    manifest_prompt_template_version: str,
    manifest_execution_plan_version: str,
    manifest_input_digest: str,
    manifest_validation_status: str,
    grant_model_version_id: str,
    grant_runtime_version: str,
    grant_prompt_template_version: str,
    grant_execution_plan_version: str,
    grant_input_digest: str,
    grant_expires_at_utc: datetime,
    requested_chunk_ids: tuple[str, ...],
    authorized_chunk_ids: tuple[str, ...],
    now: datetime | None = None,
) -> ResumeCompatibilityResult:
    current = now or datetime.now(UTC)
    if manifest_validation_status != "accepted":
        return ResumeCompatibilityResult(
            decision=ResumeCompatibilityDecision.CHECKPOINT_NOT_ACCEPTED,
            permitted=False,
            detail="checkpoint manifest not accepted",
        )
    if grant_expires_at_utc <= current:
        return ResumeCompatibilityResult(
            decision=ResumeCompatibilityDecision.GRANT_EXPIRED,
            permitted=False,
        )
    if manifest_input_digest != grant_input_digest:
        return ResumeCompatibilityResult(
            decision=ResumeCompatibilityDecision.INPUT_DIGEST_MISMATCH,
            permitted=False,
        )
    if manifest_model_version_id != grant_model_version_id:
        return ResumeCompatibilityResult(
            decision=ResumeCompatibilityDecision.INCOMPATIBLE_MODEL_SPACE,
            permitted=False,
        )
    if manifest_runtime_version != grant_runtime_version:
        return ResumeCompatibilityResult(
            decision=ResumeCompatibilityDecision.INCOMPATIBLE_RUNTIME,
            permitted=False,
        )
    if manifest_prompt_template_version != grant_prompt_template_version:
        return ResumeCompatibilityResult(
            decision=ResumeCompatibilityDecision.INCOMPATIBLE_PROMPT_TEMPLATE,
            permitted=False,
        )
    if manifest_execution_plan_version != grant_execution_plan_version:
        return ResumeCompatibilityResult(
            decision=ResumeCompatibilityDecision.INCOMPATIBLE_EXECUTION_PLAN,
            permitted=False,
        )
    authorized = set(authorized_chunk_ids)
    if any(chunk_id not in authorized for chunk_id in requested_chunk_ids):
        return ResumeCompatibilityResult(
            decision=ResumeCompatibilityDecision.UNAUTHORIZED_CHUNK,
            permitted=False,
        )
    return ResumeCompatibilityResult(
        decision=ResumeCompatibilityDecision.COMPATIBLE,
        permitted=True,
    )


class CheckpointResumeService:
    async def publish_manifest(
        self,
        connection: AsyncConnection,
        spec: CheckpointManifestSpec,
    ) -> UUID:
        manifest_id = (
            await connection.execute(
                text(
                    """
                    INSERT INTO public.checkpoint_manifests(
                      workspace_id, task_run_id, task_revision_id, task_attempt_id,
                      assignment_id, input_digest, execution_plan_id, execution_plan_version,
                      stage_id, chunk_id, chunk_index, chunker_version, tokenizer_version,
                      prompt_template_version, model_version_id, artifact_digest,
                      runtime_version, backend, producer_attempt_id, producer_assignment_id,
                      producer_fence_token, producer_worker_device_id, producer_worker_boot_id,
                      processed_ranges_json, completed_chunk_ids_json, result_artifact_hash,
                      validation_version, validation_status, checkpoint_schema_version,
                      retention_policy_version
                    ) VALUES (
                      :workspace_id, :task_run_id, :task_revision_id, :task_attempt_id,
                      :assignment_id, :input_digest, :execution_plan_id, :execution_plan_version,
                      :stage_id, :chunk_id, :chunk_index, :chunker_version, :tokenizer_version,
                      :prompt_template_version, :model_version_id, :artifact_digest,
                      :runtime_version, :backend, :producer_attempt_id, :producer_assignment_id,
                      :producer_fence_token, :producer_worker_device_id, :producer_worker_boot_id,
                      CAST(:processed_ranges_json AS jsonb), CAST(:completed_chunk_ids_json AS jsonb),
                      :result_artifact_hash, :validation_version, 'accepted',
                      :checkpoint_schema_version, :retention_policy_version
                    )
                    ON CONFLICT ON CONSTRAINT UQ_checkpoint_manifest_chunk DO UPDATE
                      SET result_artifact_hash = EXCLUDED.result_artifact_hash,
                          processed_ranges_json = EXCLUDED.processed_ranges_json,
                          completed_chunk_ids_json = EXCLUDED.completed_chunk_ids_json,
                          validation_status = 'accepted'
                    RETURNING id
                    """
                ),
                {
                    "workspace_id": spec.workspace_id,
                    "task_run_id": spec.task_run_id,
                    "task_revision_id": spec.task_revision_id,
                    "task_attempt_id": spec.task_attempt_id,
                    "assignment_id": spec.assignment_id,
                    "input_digest": spec.input_digest,
                    "execution_plan_id": spec.execution_plan_id,
                    "execution_plan_version": spec.execution_plan_version,
                    "stage_id": spec.stage_id,
                    "chunk_id": spec.chunk_id,
                    "chunk_index": spec.chunk_index,
                    "chunker_version": spec.chunker_version,
                    "tokenizer_version": spec.tokenizer_version,
                    "prompt_template_version": spec.prompt_template_version,
                    "model_version_id": spec.model_version_id,
                    "artifact_digest": spec.artifact_digest,
                    "runtime_version": spec.runtime_version,
                    "backend": spec.backend,
                    "producer_attempt_id": spec.producer_attempt_id,
                    "producer_assignment_id": spec.producer_assignment_id,
                    "producer_fence_token": spec.producer_fence_token,
                    "producer_worker_device_id": spec.producer_worker_device_id,
                    "producer_worker_boot_id": spec.producer_worker_boot_id,
                    "processed_ranges_json": json.dumps(spec.processed_ranges),
                    "completed_chunk_ids_json": json.dumps(spec.completed_chunk_ids),
                    "result_artifact_hash": spec.result_artifact_hash,
                    "validation_version": VALIDATION_VERSION,
                    "checkpoint_schema_version": CHECKPOINT_SCHEMA_VERSION,
                    "retention_policy_version": DEFAULT_RETENTION_POLICY_VERSION,
                },
            )
        ).scalar_one()
        return UUID(str(manifest_id))

    async def issue_grant(
        self,
        connection: AsyncConnection,
        spec: ResumeGrantSpec,
    ) -> UUID:
        grant_id = (
            await connection.execute(
                text(
                    """
                    SELECT public.issue_resume_grant(
                      :workspace_id,
                      :task_run_id,
                      :assignment_id,
                      :fence_token,
                      :worker_device_id,
                      :checkpoint_manifest_id,
                      :input_digest,
                      CAST(:authorized_chunk_ids AS jsonb),
                      CAST(:authorized_stage_ids AS jsonb),
                      :model_version_id,
                      :runtime_version,
                      :prompt_template_version,
                      :execution_plan_version,
                      :producer_fence_token,
                      :producer_assignment_id,
                      :expires_at_utc
                    ) AS grant_id
                    """
                ),
                {
                    "workspace_id": spec.workspace_id,
                    "task_run_id": spec.task_run_id,
                    "assignment_id": spec.assignment_id,
                    "fence_token": spec.fence_token,
                    "worker_device_id": spec.worker_device_id,
                    "checkpoint_manifest_id": spec.checkpoint_manifest_id,
                    "input_digest": spec.input_digest,
                    "authorized_chunk_ids": json.dumps(list(spec.authorized_chunk_ids)),
                    "authorized_stage_ids": json.dumps(list(spec.authorized_stage_ids)),
                    "model_version_id": spec.model_version_id,
                    "runtime_version": spec.runtime_version,
                    "prompt_template_version": spec.prompt_template_version,
                    "execution_plan_version": spec.execution_plan_version,
                    "producer_fence_token": spec.producer_fence_token,
                    "producer_assignment_id": spec.producer_assignment_id,
                    "expires_at_utc": spec.expires_at_utc,
                },
            )
        ).scalar_one()
        return UUID(str(grant_id))

    @staticmethod
    def default_grant_expiry(*, hours: int = 24) -> datetime:
        return datetime.now(UTC) + timedelta(hours=hours)

    @staticmethod
    def require_compatible(result: ResumeCompatibilityResult) -> None:
        if result.permitted:
            return
        code = {
            ResumeCompatibilityDecision.INCOMPATIBLE_MODEL_SPACE: "CHECKPOINT_INCOMPATIBLE",
            ResumeCompatibilityDecision.INCOMPATIBLE_RUNTIME: "CHECKPOINT_INCOMPATIBLE",
            ResumeCompatibilityDecision.INCOMPATIBLE_PROMPT_TEMPLATE: "CHECKPOINT_INCOMPATIBLE",
            ResumeCompatibilityDecision.INCOMPATIBLE_EXECUTION_PLAN: "CHECKPOINT_INCOMPATIBLE",
            ResumeCompatibilityDecision.INPUT_DIGEST_MISMATCH: "INPUT_DIGEST_MISMATCH",
            ResumeCompatibilityDecision.CHECKPOINT_NOT_ACCEPTED: "CHECKPOINT_NOT_SUPPORTED",
            ResumeCompatibilityDecision.GRANT_EXPIRED: "ASSIGNMENT_STALE_FENCE",
            ResumeCompatibilityDecision.UNAUTHORIZED_CHUNK: "CHECKPOINT_NOT_SUPPORTED",
        }.get(result.decision, "CHECKPOINT_NOT_SUPPORTED")
        raise worker_error(code, detail=result.detail or result.decision.value)
