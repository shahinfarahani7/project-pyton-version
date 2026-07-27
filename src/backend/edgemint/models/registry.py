from __future__ import annotations

import json
import secrets
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.building_blocks.eventing.transactional_outbox import OutboxEvent, enqueue_outbox_event
from edgemint.building_blocks.ids import EntityId, public_id
from edgemint.building_blocks.settings import Settings, get_settings
from edgemint.files.idempotency import (
    begin_idempotent_command,
    complete_idempotent_command,
    idempotency_scope,
)
from edgemint.models.compatibility import (
    DeviceResourceSnapshot,
    ModelResourceEnvelope,
    assert_device_compatible,
)
from edgemint.models.distribution import admit_chunk_download, reject_downgrade
from edgemint.models.errors import model_error
from edgemint.models.lifecycle import ModelVersionLifecycle
from edgemint.models.promotion import ReleaseEvidence, validate_promotion_gate
from edgemint.models.schemas import (
    ApproveModelRequest,
    CommandReceipt,
    CreateModelVersionRequest,
    ModelView,
    ReportModelInstallRequest,
    RevokeModelRequest,
    RollbackModelRolloutRequest,
    StartModelRolloutRequest,
)
from edgemint.models.signing import build_digest_pinned_manifest
from edgemint.security.context import AuthorizationContext
from edgemint.security.tokens import write_audit_event
from edgemint.workers.sessions import WorkerSessionContext, resolve_worker_session


@dataclass
class ModelRegistryService:
    settings: Settings = field(default_factory=get_settings)
    lifecycle: ModelVersionLifecycle = field(default_factory=ModelVersionLifecycle.load)

    def _registry_workspace_id(self) -> UUID | None:
        raw = self.settings.model_registry_workspace_id
        if not raw:
            return None
        return UUID(raw)

    async def create_model_version(
        self,
        connection: AsyncConnection,
        *,
        payload: CreateModelVersionRequest,
    ) -> ModelView:
        model_row = (
            await connection.execute(
                text("SELECT id FROM public.models WHERE public_id = :public_id LIMIT 1"),
                {"public_id": payload.modelPublicId},
            )
        ).mappings().first()
        if model_row is None:
            raise model_error("TENANT_RESOURCE_NOT_FOUND", detail="model not found")

        rollback_id: UUID | None = None
        if payload.rollbackVersionPublicId:
            rollback = (
                await connection.execute(
                    text(
                        """
                        SELECT id FROM public.model_versions
                        WHERE public_id = :public_id
                        LIMIT 1
                        """
                    ),
                    {"public_id": payload.rollbackVersionPublicId},
                )
            ).mappings().first()
            if rollback is None:
                raise model_error("TENANT_RESOURCE_NOT_FOUND", detail="rollback version not found")
            rollback_id = UUID(str(rollback["id"]))

        version_entity = EntityId.new().value
        version_public = public_id("mdv")
        manifest, signature = build_digest_pinned_manifest(
            model_version_public_id=version_public,
            artifact_sha256=payload.artifactSha256,
            artifact_size_bytes=payload.artifactSizeBytes,
            runtime_abi=payload.runtimeAbi,
            license_spdx=payload.licenseSpdx,
            chunk_size_bytes=self.settings.model_chunk_size_bytes,
            settings=self.settings,
        )
        now = datetime.now(UTC)
        await connection.execute(
            text(
                """
                INSERT INTO public.model_versions(
                    id, model_id, public_id, semantic_version, artifact_uri, artifact_sha256,
                    signature_uri, license_spdx, status, rollback_version_id, runtime_abi,
                    minimum_device_tier, peak_ram_bytes, minimum_free_storage_bytes,
                    manifest_json, signature_sha256, license_status, benchmark_evidence_path,
                    updated_at_utc
                )
                VALUES (
                    :id, :model_id, :public_id, :semantic_version, :artifact_uri, :artifact_sha256,
                    :signature_uri, :license_spdx, 'draft', :rollback_version_id, :runtime_abi,
                    :minimum_device_tier, :peak_ram_bytes, :minimum_free_storage_bytes,
                    CAST(:manifest_json AS jsonb), :signature_sha256, 'pending',
                    :benchmark_evidence_path, :updated_at_utc
                )
                """
            ),
            {
                "id": version_entity,
                "model_id": model_row["id"],
                "public_id": version_public,
                "semantic_version": payload.semanticVersion,
                "artifact_uri": payload.artifactUri,
                "artifact_sha256": payload.artifactSha256,
                "signature_uri": payload.signatureUri,
                "license_spdx": payload.licenseSpdx,
                "rollback_version_id": rollback_id,
                "runtime_abi": payload.runtimeAbi,
                "minimum_device_tier": payload.minimumDeviceTier,
                "peak_ram_bytes": payload.peakRamBytes,
                "minimum_free_storage_bytes": payload.minimumFreeStorageBytes,
                "manifest_json": json.dumps(manifest),
                "signature_sha256": signature,
                "benchmark_evidence_path": payload.benchmarkEvidencePath,
                "updated_at_utc": now,
            },
        )
        return ModelView(id=version_public, status="draft", version=1, updatedAt=now)

    async def approve_model(
        self,
        connection: AsyncConnection,
        *,
        auth: AuthorizationContext,
        model_version_public_id: str,
        payload: ApproveModelRequest,
        idempotency_key: str,
        request_id: str | None = None,
    ) -> CommandReceipt:
        workspace_id = self._registry_workspace_id()
        if workspace_id is None:
            raise model_error("MODEL_RELEASE_EVIDENCE_MISSING", detail="registry workspace not configured")
        scope = idempotency_scope(
            operation_id="approveModel",
            principal_id=auth.principal.principal_id,
            workspace_id=workspace_id,
        )
        replay = await begin_idempotent_command(
            connection,
            workspace_id=workspace_id,
            scope=scope,
            idempotency_key=idempotency_key,
            payload={"modelVersionId": model_version_public_id, **payload.model_dump(mode="json")},
        )
        if replay is not None:
            if replay.status_code == 409:
                raise model_error("IDEMPOTENCY_CONFLICT")
            return CommandReceipt.model_validate(replay.body)

        row = await self._load_version_for_update(connection, model_version_public_id)
        evidence = ReleaseEvidence(
            artifact_sha256=str(row["artifact_sha256"]),
            signature_sha256=str(row["signature_sha256"]),
            license_spdx=str(row["license_spdx"]),
            license_status="approved",
            benchmark_evidence_path=row["benchmark_evidence_path"],
            rollback_version_id=str(row["rollback_version_id"]) if row["rollback_version_id"] else None,
            manifest=dict(row["manifest_json"]),
        )
        validate_promotion_gate(evidence, settings=self.settings)
        self.lifecycle.assert_transition(str(row["status"]), "active")
        now = datetime.now(UTC)
        await connection.execute(
            text(
                """
                UPDATE public.model_versions
                SET status = 'active', license_status = 'approved', updated_at_utc = :updated_at_utc,
                    row_version = row_version + 1
                WHERE id = :id
                """
            ),
            {"id": row["id"], "updated_at_utc": now},
        )
        await write_audit_event(
            connection,
            workspace_id=workspace_id,
            actor_id=str(auth.principal.principal_id),
            action="model.approve",
            resource_type="model_version",
            resource_id=model_version_public_id,
            details={"reason": payload.reason, "ticketId": payload.ticketId},
        )
        receipt = CommandReceipt(
            operationId="approveModel",
            accepted=True,
            status="active",
            occurredAt=now,
            resourceId=model_version_public_id,
            requestId=request_id,
        )
        await complete_idempotent_command(
            connection,
            workspace_id=workspace_id,
            scope=scope,
            idempotency_key=idempotency_key,
            status_code=202,
            body=receipt.model_dump(mode="json"),
        )
        return receipt

    async def get_model_manifest(
        self,
        connection: AsyncConnection,
        *,
        session_token: str,
        model_version_public_id: str,
    ) -> ModelView:
        session = await resolve_worker_session(connection, access_token=session_token)
        row = await self._load_active_version(connection, model_version_public_id)
        await self._assert_manifest_access(connection, session=session, row=row)
        return ModelView(
            id=str(row["public_id"]),
            status=str(row["status"]),
            version=int(row["row_version"]),
            updatedAt=row["updated_at_utc"],
        )

    async def report_model_install(
        self,
        connection: AsyncConnection,
        *,
        session_token: str,
        model_version_public_id: str,
        payload: ReportModelInstallRequest,
        idempotency_key: str,
        request_id: str | None = None,
    ) -> CommandReceipt:
        session = await resolve_worker_session(connection, access_token=session_token)
        workspace_id = self._registry_workspace_id()
        if workspace_id is not None:
            scope = idempotency_scope(
                operation_id="reportModelInstall",
                principal_id=session.principal_id,
                workspace_id=workspace_id,
            )
            replay = await begin_idempotent_command(
                connection,
                workspace_id=workspace_id,
                scope=scope,
                idempotency_key=idempotency_key,
                payload=payload.model_dump(mode="json"),
            )
            if replay is not None:
                if replay.status_code == 409:
                    raise model_error("IDEMPOTENCY_CONFLICT")
                return CommandReceipt.model_validate(replay.body)

        row = await self._load_active_version(connection, model_version_public_id)
        if str(row["artifact_sha256"]) != payload.artifactSha256:
            raise model_error("MODEL_DIGEST_MISMATCH")
        manifest = dict(row["manifest_json"])
        if manifest.get("artifactSha256") != payload.artifactSha256:
            raise model_error("MODEL_DIGEST_MISMATCH")
        device = await self._load_device_snapshot(connection, session.device_id)
        assert_device_compatible(
            DeviceResourceSnapshot(
                device_tier=str(device["device_tier"]),
                runtime_abi=str(device["runtime_abi"]),
                free_ram_bytes=int(device["free_ram_bytes"]),
                free_storage_bytes=int(device["free_storage_bytes"]),
            ),
            ModelResourceEnvelope(
                minimum_device_tier=str(row["minimum_device_tier"]),
                runtime_abi=str(row["runtime_abi"]),
                peak_ram_bytes=int(row["peak_ram_bytes"]),
                minimum_free_storage_bytes=int(row["minimum_free_storage_bytes"]),
            ),
        )
        existing = await self._load_install(connection, session.device_id, UUID(str(row["id"])))
        if existing is not None:
            reject_downgrade(
                installed_version_rank=int(existing["row_version"]),
                candidate_version_rank=int(row["row_version"]),
            )
        now = datetime.now(UTC)
        if existing is None:
            await connection.execute(
                text(
                    """
                    INSERT INTO public.device_model_installs(
                        worker_device_id, model_version_id, verified_sha256, status, verified_at_utc
                    )
                    VALUES (:worker_device_id, :model_version_id, :verified_sha256, 'ready', :verified_at_utc)
                    """
                ),
                {
                    "worker_device_id": session.device_id,
                    "model_version_id": row["id"],
                    "verified_sha256": payload.artifactSha256,
                    "verified_at_utc": now,
                },
            )
        else:
            await connection.execute(
                text(
                    """
                    UPDATE public.device_model_installs
                    SET verified_sha256 = :verified_sha256,
                        status = 'ready',
                        verified_at_utc = :verified_at_utc
                    WHERE worker_device_id = :worker_device_id AND model_version_id = :model_version_id
                    """
                ),
                {
                    "worker_device_id": session.device_id,
                    "model_version_id": row["id"],
                    "verified_sha256": payload.artifactSha256,
                    "verified_at_utc": now,
                },
            )
        if workspace_id is not None:
            await enqueue_outbox_event(
                connection,
                OutboxEvent(
                    workspace_id=workspace_id,
                    event_type="model.installed",
                    aggregate_type="model_version",
                    aggregate_id=model_version_public_id,
                    aggregate_sequence=int(row["row_version"]),
                    cloud_event={
                        "specversion": "1.0",
                        "type": "model.installed",
                        "source": "model-registry",
                        "id": secrets.token_hex(16),
                        "time": now.isoformat(),
                        "data": {
                            "modelVersionId": model_version_public_id,
                            "deviceId": session.device_public_id,
                            "artifactSha256": payload.artifactSha256,
                        },
                    },
                ),
            )
        receipt = CommandReceipt(
            operationId="reportModelInstall",
            accepted=True,
            status="active",
            occurredAt=now,
            resourceId=model_version_public_id,
            requestId=request_id,
        )
        if workspace_id is not None:
            scope = idempotency_scope(
                operation_id="reportModelInstall",
                principal_id=session.principal_id,
                workspace_id=workspace_id,
            )
            await complete_idempotent_command(
                connection,
                workspace_id=workspace_id,
                scope=scope,
                idempotency_key=idempotency_key,
                status_code=200,
                body=receipt.model_dump(mode="json"),
            )
        return receipt

    async def start_model_rollout(
        self,
        connection: AsyncConnection,
        *,
        auth: AuthorizationContext,
        payload: StartModelRolloutRequest,
        idempotency_key: str,
        request_id: str | None = None,
    ) -> CommandReceipt:
        workspace_id = self._registry_workspace_id()
        if workspace_id is None:
            raise model_error("MODEL_ROLLOUT_ALREADY_ACTIVE", detail="registry workspace not configured")
        scope = idempotency_scope(
            operation_id="startModelRollout",
            principal_id=auth.principal.principal_id,
            workspace_id=workspace_id,
        )
        replay = await begin_idempotent_command(
            connection,
            workspace_id=workspace_id,
            scope=scope,
            idempotency_key=idempotency_key,
            payload=payload.model_dump(mode="json"),
        )
        if replay is not None:
            if replay.status_code == 409:
                raise model_error("IDEMPOTENCY_CONFLICT")
            return CommandReceipt.model_validate(replay.body)

        version = await self._load_active_version(connection, payload.modelVersionId)
        active_rollout = (
            await connection.execute(
                text(
                    """
                    SELECT id FROM public.model_rollouts
                    WHERE model_version_id = :model_version_id AND status = 'active'
                    LIMIT 1
                    """
                ),
                {"model_version_id": version["id"]},
            )
        ).first()
        if active_rollout is not None:
            raise model_error("MODEL_ROLLOUT_ALREADY_ACTIVE")

        rollout_id = EntityId.new().value
        rollout_public = public_id("mro")
        now = datetime.now(UTC)
        await connection.execute(
            text(
                """
                INSERT INTO public.model_rollouts(
                    id, public_id, model_version_id, rollout_percent, status, rollback_version_id
                )
                VALUES (
                    :id, :public_id, :model_version_id, :rollout_percent, 'active', :rollback_version_id
                )
                """
            ),
            {
                "id": rollout_id,
                "public_id": rollout_public,
                "model_version_id": version["id"],
                "rollout_percent": payload.initialPercentage,
                "rollback_version_id": version["rollback_version_id"],
            },
        )
        await enqueue_outbox_event(
            connection,
            OutboxEvent(
                workspace_id=workspace_id,
                event_type="model.rollout.started",
                aggregate_type="model_rollout",
                aggregate_id=rollout_public,
                aggregate_sequence=1,
                cloud_event={
                    "specversion": "1.0",
                    "type": "model.rollout.started",
                    "source": "model-registry",
                    "id": secrets.token_hex(16),
                    "time": now.isoformat(),
                    "data": {
                        "modelVersionId": payload.modelVersionId,
                        "rolloutPercent": payload.initialPercentage,
                    },
                },
            ),
        )
        receipt = CommandReceipt(
            operationId="startModelRollout",
            accepted=True,
            status="active",
            occurredAt=now,
            resourceId=rollout_public,
            requestId=request_id,
        )
        await complete_idempotent_command(
            connection,
            workspace_id=workspace_id,
            scope=scope,
            idempotency_key=idempotency_key,
            status_code=202,
            body=receipt.model_dump(mode="json"),
        )
        return receipt

    async def revoke_model(
        self,
        connection: AsyncConnection,
        *,
        auth: AuthorizationContext,
        model_version_public_id: str,
        payload: RevokeModelRequest,
        idempotency_key: str,
        request_id: str | None = None,
    ) -> CommandReceipt:
        if not payload.reason.strip():
            raise model_error("MODEL_REVOCATION_REASON_REQUIRED")
        workspace_id = self._registry_workspace_id()
        if workspace_id is None:
            raise model_error("TENANT_RESOURCE_NOT_FOUND", detail="registry workspace not configured")
        row = await self._load_version_for_update(connection, model_version_public_id)
        now = datetime.now(UTC)
        await connection.execute(
            text(
                """
                UPDATE public.model_versions
                SET status = 'revoked', updated_at_utc = :updated_at_utc, row_version = row_version + 1
                WHERE id = :id
                """
            ),
            {"id": row["id"], "updated_at_utc": now},
        )
        await enqueue_outbox_event(
            connection,
            OutboxEvent(
                workspace_id=workspace_id,
                event_type="model.revoked",
                aggregate_type="model_version",
                aggregate_id=model_version_public_id,
                aggregate_sequence=int(row["row_version"]) + 1,
                cloud_event={
                    "specversion": "1.0",
                    "type": "model.revoked",
                    "source": "model-registry",
                    "id": secrets.token_hex(16),
                    "time": now.isoformat(),
                    "data": {"modelVersionId": model_version_public_id, "reason": payload.reason},
                },
            ),
        )
        _ = auth
        _ = idempotency_key
        return CommandReceipt(
            operationId="revokeModel",
            accepted=True,
            status="revoked",
            occurredAt=now,
            resourceId=model_version_public_id,
            requestId=request_id,
        )

    async def rollback_model_rollout(
        self,
        connection: AsyncConnection,
        *,
        auth: AuthorizationContext,
        rollout_public_id: str,
        payload: RollbackModelRolloutRequest,
        idempotency_key: str,
        request_id: str | None = None,
    ) -> CommandReceipt:
        workspace_id = self._registry_workspace_id()
        if workspace_id is None:
            raise model_error("TENANT_RESOURCE_NOT_FOUND", detail="registry workspace not configured")
        rollout = (
            await connection.execute(
                text(
                    """
                    SELECT id, model_version_id, rollback_version_id, status
                    FROM public.model_rollouts
                    WHERE public_id = :public_id
                    FOR UPDATE
                    """
                ),
                {"public_id": rollout_public_id},
            )
        ).mappings().first()
        if rollout is None:
            raise model_error("TENANT_RESOURCE_NOT_FOUND", detail="rollout not found")
        if rollout["rollback_version_id"] is None:
            raise model_error("MODEL_RELEASE_EVIDENCE_MISSING", detail="rollback version missing")
        now = datetime.now(UTC)
        await connection.execute(
            text(
                """
                UPDATE public.model_rollouts
                SET status = 'rolled_back'
                WHERE id = :id
                """
            ),
            {"id": rollout["id"]},
        )
        await connection.execute(
            text(
                """
                UPDATE public.model_versions
                SET status = 'deprecated', updated_at_utc = :updated_at_utc
                WHERE id = :id
                """
            ),
            {"id": rollout["model_version_id"], "updated_at_utc": now},
        )
        await connection.execute(
            text(
                """
                UPDATE public.model_versions
                SET status = 'active', updated_at_utc = :updated_at_utc
                WHERE id = :id
                """
            ),
            {"id": rollout["rollback_version_id"], "updated_at_utc": now},
        )
        _ = auth
        _ = payload
        _ = idempotency_key
        return CommandReceipt(
            operationId="rollbackModelRollout",
            accepted=True,
            status="active",
            occurredAt=now,
            resourceId=rollout_public_id,
            requestId=request_id,
        )

    async def admit_download_chunk(
        self,
        connection: AsyncConnection,
        *,
        session: WorkerSessionContext,
        model_version_public_id: str,
        chunk_index: int,
        chunk_sha256: str,
    ) -> None:
        row = await self._load_active_version(connection, model_version_public_id)
        manifest = dict(row["manifest_json"])
        chunks = manifest.get("chunks") or []
        if chunk_index >= len(chunks):
            raise model_error("MODEL_DIGEST_MISMATCH", detail="unknown chunk")
        expected = str(chunks[chunk_index]["sha256"])
        download = (
            await connection.execute(
                text(
                    """
                    SELECT id, last_chunk_index
                    FROM public.model_downloads
                    WHERE worker_device_id = :worker_device_id AND model_version_id = :model_version_id
                    FOR UPDATE
                    """
                ),
                {"worker_device_id": session.device_id, "model_version_id": row["id"]},
            )
        ).mappings().first()
        last_index = -1 if download is None else int(download["last_chunk_index"])
        new_index = admit_chunk_download(
            last_chunk_index=last_index,
            chunk_index=chunk_index,
            chunk_sha256=chunk_sha256,
            expected_sha256=expected,
        )
        if download is None:
            await connection.execute(
                text(
                    """
                    INSERT INTO public.model_downloads(
                        worker_device_id, model_version_id, status, bytes_downloaded, last_chunk_index
                    )
                    VALUES (
                        :worker_device_id, :model_version_id, 'downloading',
                        :bytes_downloaded, :last_chunk_index
                    )
                    """
                ),
                {
                    "worker_device_id": session.device_id,
                    "model_version_id": row["id"],
                    "bytes_downloaded": int(chunks[chunk_index]["sizeBytes"]),
                    "last_chunk_index": new_index,
                },
            )
        else:
            await connection.execute(
                text(
                    """
                    UPDATE public.model_downloads
                    SET last_chunk_index = :last_chunk_index,
                        bytes_downloaded = bytes_downloaded + :chunk_size,
                        status = 'downloading'
                    WHERE id = :id
                    """
                ),
                {
                    "id": download["id"],
                    "last_chunk_index": new_index,
                    "chunk_size": int(chunks[chunk_index]["sizeBytes"]),
                },
            )

    async def _load_version_for_update(
        self, connection: AsyncConnection, model_version_public_id: str
    ) -> dict[str, Any]:
        row = (
            await connection.execute(
                text(
                    """
                    SELECT id, public_id, status, artifact_sha256, signature_sha256, license_spdx,
                           license_status, benchmark_evidence_path, rollback_version_id,
                           manifest_json, row_version, updated_at_utc
                    FROM public.model_versions
                    WHERE public_id = :public_id
                    FOR UPDATE
                    """
                ),
                {"public_id": model_version_public_id},
            )
        ).mappings().first()
        if row is None:
            raise model_error("TENANT_RESOURCE_NOT_FOUND", detail="model version not found")
        return dict(row)

    async def _load_active_version(
        self, connection: AsyncConnection, model_version_public_id: str
    ) -> dict[str, Any]:
        row = (
            await connection.execute(
                text(
                    """
                    SELECT id, public_id, status, artifact_sha256, signature_sha256, license_spdx,
                           license_status, benchmark_evidence_path, rollback_version_id,
                           manifest_json, row_version, updated_at_utc, minimum_device_tier,
                           runtime_abi, peak_ram_bytes, minimum_free_storage_bytes
                    FROM public.model_versions
                    WHERE public_id = :public_id
                    LIMIT 1
                    """
                ),
                {"public_id": model_version_public_id},
            )
        ).mappings().first()
        if row is None:
            raise model_error("TENANT_RESOURCE_NOT_FOUND", detail="model version not found")
        row = dict(row)
        if str(row["status"]) == "revoked":
            raise model_error("MODEL_SIGNATURE_INVALID", detail="model revoked")
        if str(row["status"]) != "active":
            raise model_error("TENANT_RESOURCE_NOT_FOUND", detail="model version not active")
        return row

    async def _assert_manifest_access(
        self,
        connection: AsyncConnection,
        *,
        session: WorkerSessionContext,
        row: dict[str, Any],
    ) -> None:
        device = await self._load_device_snapshot(connection, session.device_id)
        assert_device_compatible(
            DeviceResourceSnapshot(
                device_tier=str(device["device_tier"]),
                runtime_abi=str(device["runtime_abi"]),
                free_ram_bytes=int(device["free_ram_bytes"]),
                free_storage_bytes=int(device["free_storage_bytes"]),
            ),
            ModelResourceEnvelope(
                minimum_device_tier=str(row["minimum_device_tier"]),
                runtime_abi=str(row["runtime_abi"]),
                peak_ram_bytes=int(row["peak_ram_bytes"]),
                minimum_free_storage_bytes=int(row["minimum_free_storage_bytes"]),
            ),
        )

    async def _load_device_snapshot(self, connection: AsyncConnection, device_id: UUID) -> dict[str, Any]:
        row = (
            await connection.execute(
                text(
                    """
                    SELECT device.device_tier, device.runtime_abi,
                           COALESCE(hb.free_ram_bytes, 0) AS free_ram_bytes,
                           COALESCE(hb.free_storage_bytes, 0) AS free_storage_bytes
                    FROM public.worker_devices AS device
                    LEFT JOIN LATERAL (
                        SELECT free_ram_bytes, free_storage_bytes
                        FROM public.worker_heartbeats
                        WHERE worker_device_id = device.id
                        ORDER BY sequence_number DESC
                        LIMIT 1
                    ) AS hb ON TRUE
                    WHERE device.id = :device_id
                    """
                ),
                {"device_id": device_id},
            )
        ).mappings().first()
        if row is None:
            raise model_error("TENANT_RESOURCE_NOT_FOUND", detail="device not found")
        return dict(row)

    async def _load_install(
        self, connection: AsyncConnection, device_id: UUID, model_version_id: UUID
    ) -> dict[str, Any] | None:
        return (
            await connection.execute(
                text(
                    """
                    SELECT install.verified_sha256, version.row_version
                    FROM public.device_model_installs AS install
                    JOIN public.model_versions AS version ON version.id = install.model_version_id
                    WHERE install.worker_device_id = :device_id
                      AND install.model_version_id = :model_version_id
                    """
                ),
                {"device_id": device_id, "model_version_id": model_version_id},
            )
        ).mappings().first()
