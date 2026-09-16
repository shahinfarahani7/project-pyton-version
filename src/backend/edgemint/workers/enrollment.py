from __future__ import annotations

import json
import secrets
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
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
from edgemint.security.tokens import write_audit_event
from edgemint.routing.memory_accounting import WorkerMemoryAccountingService
from edgemint.workers.attestation import (
    new_challenge,
    public_key_fingerprint,
    verify_attestation,
)
from edgemint.workers.calibration import WorkerCalibrationProfileView, WorkerCalibrationService
from edgemint.workers.heartbeat_telemetry import telemetry_json_from_heartbeat
from edgemint.workers.errors import worker_error
from edgemint.workers.lifecycle import WorkerLifecycle
from edgemint.workers.readiness import derive_device_tier
from edgemint.workers.consent_opt_in import (
    record_contribution_opt_in_event,
    validate_contribution_mode_change,
)
from edgemint.workers.contribution_enforcement import WorkerCpuEnforcementService
from edgemint.workers.resource_policy import approved_percent_for_mode, default_contribution_mode_id
from edgemint.workers.schemas import (
    CommandReceipt,
    CreateChallengeRequest,
    CreateChallengeResponse,
    DeviceRegistrationRequest,
    HeartbeatRequest,
    RefreshSessionRequest,
    RefreshWorkerSessionResponse,
    RegisterWorkerDeviceResponse,
    ReplaceWorkerPreferencesRequest,
    SubmitBenchmarkRequest,
    WorkerPreferencesView,
    WorkerSchedule,
)
from edgemint.workers.sessions import issue_session_token, persist_worker_session


@dataclass
class WorkerEnrollmentService:
    settings: Settings = field(default_factory=get_settings)
    lifecycle: WorkerLifecycle = field(default_factory=WorkerLifecycle.load)
    calibration: WorkerCalibrationService = field(default_factory=WorkerCalibrationService)
    memory_accounting: WorkerMemoryAccountingService = field(default_factory=WorkerMemoryAccountingService)
    cpu_enforcement: WorkerCpuEnforcementService = field(default_factory=WorkerCpuEnforcementService)

    def _registry_workspace_id(self) -> UUID | None:
        raw = self.settings.worker_registry_workspace_id
        if not raw:
            return None
        return UUID(raw)

    async def create_device_challenge(
        self,
        connection: AsyncConnection,
        *,
        payload: CreateChallengeRequest,
        idempotency_key: str,
    ) -> CreateChallengeResponse:
        workspace_id = self._registry_workspace_id()
        if workspace_id is not None:
            scope = idempotency_scope(
                operation_id="createDeviceChallenge",
                principal_id=UUID(int=0),
                workspace_id=workspace_id,
            )
            replay = await begin_idempotent_command(
                connection,
                workspace_id=workspace_id,
                scope=scope,
                idempotency_key=idempotency_key,
                payload={"installationId": payload.installationId},
            )
            if replay is not None:
                if replay.status_code == 409:
                    raise worker_error("IDEMPOTENCY_CONFLICT")
                return CreateChallengeResponse.model_validate(replay.body)

        bundle = new_challenge(settings=self.settings)
        await connection.execute(
            text(
                """
                INSERT INTO public.device_challenges(
                    id, installation_id, challenge_hash, expires_at_utc
                )
                VALUES (:id, :installation_id, :challenge_hash, :expires_at_utc)
                """
            ),
            {
                "id": bundle.challenge_id,
                "installation_id": payload.installationId,
                "challenge_hash": bundle.challenge_hash,
                "expires_at_utc": bundle.expires_at,
            },
        )
        response = CreateChallengeResponse(
            challengeId=str(bundle.challenge_id),
            nonce=bundle.nonce,
            expiresAt=bundle.expires_at,
        )
        if workspace_id is not None:
            scope = idempotency_scope(
                operation_id="createDeviceChallenge",
                principal_id=UUID(int=0),
                workspace_id=workspace_id,
            )
            await complete_idempotent_command(
                connection,
                workspace_id=workspace_id,
                scope=scope,
                idempotency_key=idempotency_key,
                status_code=201,
                body=response.model_dump(mode="json"),
            )
        return response

    async def register_worker_device(
        self,
        connection: AsyncConnection,
        *,
        payload: DeviceRegistrationRequest,
        idempotency_key: str,
    ) -> RegisterWorkerDeviceResponse:
        workspace_id = self._registry_workspace_id()
        if workspace_id is not None:
            scope = idempotency_scope(
                operation_id="registerWorkerDevice",
                principal_id=UUID(int=0),
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
                    raise worker_error("IDEMPOTENCY_CONFLICT")
                return RegisterWorkerDeviceResponse.model_validate(replay.body)

        existing = await self._load_device_by_installation(connection, payload.installationId)
        if existing is not None:
            return await self._issue_registration_response(connection, existing)

        challenge = await self._consume_challenge(
            connection,
            installation_id=payload.installationId,
            attestation=payload.attestation,
        )
        verify_attestation(
            attestation=payload.attestation,
            challenge_nonce=challenge["nonce"],
            public_key_pem=payload.publicKey,
            platform=payload.platform,
            settings=self.settings,
        )
        key_fingerprint: str | None = None
        if payload.publicKey:
            key_fingerprint = public_key_fingerprint(payload.publicKey)
            duplicate = await self._load_device_by_public_key(connection, key_fingerprint)
            if duplicate is not None and duplicate["installation_id"] != payload.installationId:
                raise worker_error("DEVICE_KEY_MISMATCH", detail="cloned device key")

        principal_id = EntityId.new().value
        worker_id = EntityId.new().value
        worker_public = public_id("wrk")
        device_id = EntityId.new().value
        device_public = public_id("dev")
        attestation_expires = datetime.now(UTC) + timedelta(hours=self.settings.worker_attestation_ttl_hours)
        capability = payload.capabilities
        runtime_abi = capability.runtimeAbi
        region_code = capability.regionCode
        device_tier = capability.deviceTier
        capability_json = json.dumps(capability.model_dump(mode="json"))

        await connection.execute(
            text(
                """
                INSERT INTO public.principals(id, subject, principal_type, display_name)
                VALUES (:id, :subject, 'worker', :display_name)
                """
            ),
            {
                "id": principal_id,
                "subject": f"worker:{payload.installationId}",
                "display_name": f"Worker {worker_public}",
            },
        )
        await connection.execute(
            text(
                """
                INSERT INTO public.workers(id, principal_id, public_id, status, reliability_bps)
                VALUES (:id, :principal_id, :public_id, 'attesting', 6500)
                """
            ),
            {
                "id": worker_id,
                "principal_id": principal_id,
                "public_id": worker_public,
            },
        )
        await connection.execute(
            text(
                """
                INSERT INTO public.worker_devices(
                    id, worker_id, public_id, platform, app_version, runtime_abi, region_code,
                    device_tier, attestation_status, attestation_expires_at_utc, status,
                    installation_id, public_key_fingerprint, capability_snapshot_json
                )
                VALUES (
                    :id, :worker_id, :public_id, :platform, :app_version, :runtime_abi, :region_code,
                    :device_tier, 'verified', :attestation_expires_at_utc, 'active',
                    :installation_id, :public_key_fingerprint, CAST(:capability_snapshot_json AS jsonb)
                )
                """
            ),
            {
                "id": device_id,
                "worker_id": worker_id,
                "public_id": device_public,
                "platform": payload.platform,
                "app_version": payload.appVersion,
                "runtime_abi": runtime_abi,
                "region_code": region_code,
                "device_tier": device_tier,
                "attestation_expires_at_utc": attestation_expires,
                "installation_id": payload.installationId,
                "public_key_fingerprint": key_fingerprint,
                "capability_snapshot_json": capability_json,
            },
        )
        await connection.execute(
            text(
                """
                INSERT INTO public.worker_consents(worker_id, policy_version, accepted_at_utc)
                VALUES (:worker_id, :policy_version, :accepted_at_utc)
                """
            ),
            {
                "worker_id": worker_id,
                "policy_version": self.settings.worker_consent_policy_version,
                "accepted_at_utc": datetime.now(UTC),
            },
        )
        await connection.execute(
            text(
                """
                INSERT INTO public.worker_preferences(
                    worker_id, availability, network_policy, charging_policy,
                    minimum_battery_percent, schedule_json, schedule_mode,
                    contribution_mode_id
                )
                VALUES (
                    :worker_id, 'unavailable', 'wifi_only', 'preferred',
                    25, CAST(:schedule_json AS jsonb), 'always',
                    :contribution_mode_id
                )
                """
            ),
            {
                "worker_id": worker_id,
                "schedule_json": json.dumps({"mode": "always", "timezone": "UTC"}),
                "contribution_mode_id": default_contribution_mode_id(),
            },
        )
        self.lifecycle.assert_transition("registered", "attesting")

        access_token, token_hash, expires_at = issue_session_token(settings=self.settings)
        await persist_worker_session(
            connection,
            worker_device_id=device_id,
            token_hash=token_hash,
            expires_at=expires_at,
        )

        if workspace_id is not None:
            await enqueue_outbox_event(
                connection,
                OutboxEvent(
                    workspace_id=workspace_id,
                    event_type="worker.attested",
                    aggregate_type="worker",
                    aggregate_id=worker_public,
                    aggregate_sequence=1,
                    cloud_event={
                        "specversion": "1.0",
                        "type": "worker.attested",
                        "source": "worker-registry",
                        "id": secrets.token_hex(16),
                        "time": datetime.now(UTC).isoformat(),
                        "data": {
                            "workerId": worker_public,
                            "deviceId": device_public,
                            "platform": payload.platform,
                        },
                    },
                ),
            )
            await write_audit_event(
                connection,
                workspace_id=workspace_id,
                actor_id=str(principal_id),
                action="worker.register",
                resource_type="worker",
                resource_id=worker_public,
                details={"deviceId": device_public, "platform": payload.platform},
            )

        response = RegisterWorkerDeviceResponse(
            workerId=worker_public,
            deviceId=device_public,
            accessToken=access_token,
            expiresAt=expires_at,
        )
        if workspace_id is not None:
            scope = idempotency_scope(
                operation_id="registerWorkerDevice",
                principal_id=UUID(int=0),
                workspace_id=workspace_id,
            )
            await complete_idempotent_command(
                connection,
                workspace_id=workspace_id,
                scope=scope,
                idempotency_key=idempotency_key,
                status_code=201,
                body=response.model_dump(mode="json"),
            )
        return response

    async def refresh_worker_session(
        self,
        connection: AsyncConnection,
        *,
        payload: RefreshSessionRequest,
        idempotency_key: str,
    ) -> RefreshWorkerSessionResponse:
        from edgemint.workers.sessions import resolve_worker_session

        session = await resolve_worker_session(connection, access_token=payload.refreshToken)
        access_token, token_hash, expires_at = issue_session_token(settings=self.settings)
        await persist_worker_session(
            connection,
            worker_device_id=session.device_id,
            token_hash=token_hash,
            expires_at=expires_at,
        )
        return RefreshWorkerSessionResponse(
            workerId=session.worker_public_id,
            deviceId=session.device_public_id,
            accessToken=access_token,
            expiresAt=expires_at,
        )

    async def send_heartbeat(
        self,
        connection: AsyncConnection,
        *,
        session_token: str,
        worker_public_id: str,
        payload: HeartbeatRequest,
        idempotency_key: str,
        request_id: str | None = None,
    ) -> CommandReceipt:
        from edgemint.workers.sessions import resolve_worker_session

        session = await resolve_worker_session(
            connection,
            access_token=session_token,
            expected_worker_public_id=worker_public_id,
        )
        workspace_id = self._registry_workspace_id()
        if workspace_id is not None:
            scope = idempotency_scope(
                operation_id="sendHeartbeat",
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
                    raise worker_error("IDEMPOTENCY_CONFLICT")
                return CommandReceipt.model_validate(replay.body)

        last_sequence = await self._last_heartbeat_sequence(connection, session.device_id)
        if payload.sequence <= last_sequence:
            raise worker_error(
                "HEARTBEAT_SEQUENCE_INVALID",
                detail=f"replay or stale sequence; lastSequence={last_sequence}",
            )

        now = datetime.now(UTC)
        capability_json = (
            json.dumps(payload.capabilitySnapshot.model_dump(mode="json"))
            if payload.capabilitySnapshot is not None
            else None
        )
        telemetry_payload = telemetry_json_from_heartbeat(payload)
        telemetry_json = json.dumps(telemetry_payload) if telemetry_payload is not None else None
        await connection.execute(
            text(
                """
                INSERT INTO public.worker_heartbeats(
                    worker_device_id, sequence_number, observed_at_utc, battery_bps, charging,
                    thermal_state, free_ram_bytes, free_storage_bytes, network_type,
                    current_leases_json, installed_models_json, capability_snapshot_json,
                    telemetry_json, received_at_utc
                )
                VALUES (
                    :worker_device_id, :sequence_number, :observed_at_utc, :battery_bps, :charging,
                    :thermal_state, :free_ram_bytes, :free_storage_bytes, :network_type,
                    CAST(:current_leases_json AS jsonb), CAST(:installed_models_json AS jsonb),
                    CAST(:capability_snapshot_json AS jsonb), CAST(:telemetry_json AS jsonb),
                    :received_at_utc
                )
                """
            ),
            {
                "worker_device_id": session.device_id,
                "sequence_number": payload.sequence,
                "observed_at_utc": payload.observedAt,
                "battery_bps": payload.batteryBps,
                "charging": payload.charging,
                "thermal_state": payload.thermalState,
                "free_ram_bytes": payload.freeRamBytes,
                "free_storage_bytes": payload.freeStorageBytes,
                "network_type": payload.network,
                "current_leases_json": json.dumps(payload.currentLeases),
                "installed_models_json": json.dumps(payload.installedModels),
                "capability_snapshot_json": capability_json,
                "telemetry_json": telemetry_json,
                "received_at_utc": now,
            },
        )
        if payload.capabilitySnapshot is not None:
            await connection.execute(
                text(
                    """
                    UPDATE public.worker_devices
                    SET capability_snapshot_json = CAST(:capability_snapshot_json AS jsonb),
                        last_seen_at_utc = :last_seen_at_utc
                    WHERE id = :device_id
                    """
                ),
                {
                    "device_id": session.device_id,
                    "capability_snapshot_json": capability_json,
                    "last_seen_at_utc": now,
                },
            )
        else:
            await connection.execute(
                text(
                    """
                    UPDATE public.worker_devices
                    SET last_seen_at_utc = :last_seen_at_utc
                    WHERE id = :device_id
                    """
                ),
                {"device_id": session.device_id, "last_seen_at_utc": now},
            )
        await self.memory_accounting.ensure_base_commitment(
            connection,
            worker_device_id=session.device_id,
            snapshot_sequence=payload.sequence,
        )
        if payload.loadedModelIds:
            await self.memory_accounting.sync_resident_models(
                connection,
                worker_device_id=session.device_id,
                loaded_model_ids=list(payload.loadedModelIds),
                snapshot_sequence=payload.sequence,
            )
        contribution_mode_id = (
            payload.consentSnapshot.contributionModeId
            if payload.consentSnapshot is not None and payload.consentSnapshot.contributionModeId
            else default_contribution_mode_id()
        )
        if payload.consentSnapshot is not None or payload.cpuUsageBps is not None:
            await self.cpu_enforcement.sync_from_heartbeat(
                connection,
                worker_device_id=session.device_id,
                contribution_mode_id=contribution_mode_id,
                approved_percent=approved_percent_for_mode(contribution_mode_id),
                observed_cpu_usage_bps=payload.cpuUsageBps,
                snapshot_sequence=payload.sequence,
            )
        receipt = CommandReceipt(
            operationId="sendHeartbeat",
            accepted=True,
            status="accepted",
            occurredAt=now,
            resourceId=worker_public_id,
            requestId=request_id,
        )
        if workspace_id is not None:
            scope = idempotency_scope(
                operation_id="sendHeartbeat",
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

    async def replace_worker_preferences(
        self,
        connection: AsyncConnection,
        *,
        session_token: str,
        payload: ReplaceWorkerPreferencesRequest,
        idempotency_key: str,
        request_id: str | None = None,
    ) -> CommandReceipt:
        from edgemint.workers.sessions import resolve_worker_session

        session = await resolve_worker_session(connection, access_token=session_token)
        row = (
            await connection.execute(
                text(
                    """
                    SELECT version, availability
                    FROM public.worker_preferences
                    WHERE worker_id = :worker_id
                    FOR UPDATE
                    """
                ),
                {"worker_id": session.worker_id},
            )
        ).mappings().first()
        if row is None:
            raise worker_error("TENANT_RESOURCE_NOT_FOUND", detail="preferences missing")
        if int(row["version"]) != payload.expectedVersion:
            raise worker_error("VERSION_CONFLICT")
        current_mode_id = str(
            (
                await connection.execute(
                    text(
                        """
                        SELECT contribution_mode_id
                        FROM public.worker_preferences
                        WHERE worker_id = :worker_id
                        """
                    ),
                    {"worker_id": session.worker_id},
                )
            ).scalar_one()
        )
        try:
            requested_mode = validate_contribution_mode_change(
                current_mode_id=current_mode_id,
                requested_mode_id=payload.contributionModeId,
                performance_opt_in_confirmed=payload.performanceOptInConfirmed,
            )
        except ValueError as exc:
            raise worker_error("INPUT_SCHEMA_INVALID", detail=str(exc)) from exc

        now = datetime.now(UTC)
        await connection.execute(
            text(
                """
                UPDATE public.worker_preferences
                SET availability = :availability,
                    network_policy = :network_policy,
                    charging_policy = :charging_policy,
                    minimum_battery_percent = :minimum_battery_percent,
                    schedule_json = CAST(:schedule_json AS jsonb),
                    schedule_mode = :schedule_mode,
                    contribution_mode_id = :contribution_mode_id,
                    updated_at_utc = :updated_at_utc,
                    version = version + 1
                WHERE worker_id = :worker_id
                """
            ),
            {
                "worker_id": session.worker_id,
                "availability": payload.availability,
                "network_policy": payload.networkPolicy,
                "charging_policy": payload.chargingPolicy,
                "minimum_battery_percent": payload.minimumBatteryPercent,
                "schedule_json": json.dumps(payload.schedule.model_dump(mode="json")),
                "schedule_mode": payload.schedule.mode,
                "contribution_mode_id": payload.contributionModeId,
                "updated_at_utc": now,
            },
        )
        if requested_mode.requiresExplicitOptIn and payload.contributionModeId != current_mode_id:
            await record_contribution_opt_in_event(
                connection,
                worker_id=session.worker_id,
                contribution_mode_id=payload.contributionModeId,
                opt_in_confirmed=payload.performanceOptInConfirmed,
                request_id=request_id,
            )
        return CommandReceipt(
            operationId="replaceWorkerPreferences",
            accepted=True,
            status="accepted",
            occurredAt=now,
            resourceId=session.worker_public_id,
            requestId=request_id,
        )

    async def get_worker_preferences(
        self,
        connection: AsyncConnection,
        *,
        session_token: str,
    ) -> WorkerPreferencesView:
        from edgemint.workers.sessions import resolve_worker_session

        session = await resolve_worker_session(connection, access_token=session_token)
        row = (
            await connection.execute(
                text(
                    """
                    SELECT version, availability, network_policy, charging_policy,
                           minimum_battery_percent, schedule_json, contribution_mode_id
                    FROM public.worker_preferences
                    WHERE worker_id = :worker_id
                    """
                ),
                {"worker_id": session.worker_id},
            )
        ).mappings().first()
        if row is None:
            raise worker_error("TENANT_RESOURCE_NOT_FOUND")
        schedule = WorkerSchedule.model_validate(dict(row["schedule_json"]))
        return WorkerPreferencesView(
            version=int(row["version"]),
            availability=row["availability"],
            networkPolicy=row["network_policy"],
            chargingPolicy=row["charging_policy"],
            minimumBatteryPercent=int(row["minimum_battery_percent"]),
            contributionModeId=str(row["contribution_mode_id"]),
            schedule=schedule,
        )

    async def _consume_challenge(
        self,
        connection: AsyncConnection,
        *,
        installation_id: str,
        attestation: dict[str, Any],
    ) -> dict[str, str]:
        challenge_id = attestation.get("challengeId")
        if not challenge_id:
            raise worker_error("INPUT_SCHEMA_INVALID", detail="attestation.challengeId required")
        row = (
            await connection.execute(
                text(
                    """
                    SELECT id, challenge_hash, expires_at_utc, used_at_utc, installation_id
                    FROM public.device_challenges
                    WHERE id = CAST(:challenge_id AS uuid)
                    FOR UPDATE
                    """
                ),
                {"challenge_id": challenge_id},
            )
        ).mappings().first()
        if row is None:
            raise worker_error("TENANT_RESOURCE_NOT_FOUND", detail="challenge not found")
        if row["installation_id"] and row["installation_id"] != installation_id:
            raise worker_error("ATTESTATION_INVALID", detail="installation mismatch")
        if row["used_at_utc"] is not None:
            raise worker_error("ATTESTATION_INVALID", detail="challenge already used")
        if row["expires_at_utc"] < datetime.now(UTC):
            raise worker_error("CHALLENGE_EXPIRED")
        nonce = attestation.get("nonce") or attestation.get("challengeNonce")
        if not nonce:
            raise worker_error("ATTESTATION_INVALID", detail="attestation nonce required")
        import hashlib

        digest = hashlib.sha256(str(nonce).encode("utf-8")).digest()
        if digest != bytes(row["challenge_hash"]):
            raise worker_error("ATTESTATION_INVALID", detail="nonce hash mismatch")
        await connection.execute(
            text(
                """
                UPDATE public.device_challenges
                SET used_at_utc = :used_at_utc
                WHERE id = :id
                """
            ),
            {"id": row["id"], "used_at_utc": datetime.now(UTC)},
        )
        return {"nonce": str(nonce)}

    async def _load_device_by_installation(
        self, connection: AsyncConnection, installation_id: str
    ) -> dict[str, Any] | None:
        return (
            await connection.execute(
                text(
                    """
                    SELECT device.id AS device_id, device.public_id AS device_public_id,
                           worker.id AS worker_id, worker.public_id AS worker_public_id
                    FROM public.worker_devices AS device
                    JOIN public.workers AS worker ON worker.id = device.worker_id
                    WHERE device.installation_id = :installation_id
                    LIMIT 1
                    """
                ),
                {"installation_id": installation_id},
            )
        ).mappings().first()

    async def _load_device_by_public_key(
        self, connection: AsyncConnection, fingerprint: str
    ) -> dict[str, Any] | None:
        return (
            await connection.execute(
                text(
                    """
                    SELECT installation_id
                    FROM public.worker_devices
                    WHERE public_key_fingerprint = :fingerprint
                    LIMIT 1
                    """
                ),
                {"fingerprint": fingerprint},
            )
        ).mappings().first()

    async def _issue_registration_response(
        self, connection: AsyncConnection, existing: dict[str, Any]
    ) -> RegisterWorkerDeviceResponse:
        access_token, token_hash, expires_at = issue_session_token(settings=self.settings)
        await persist_worker_session(
            connection,
            worker_device_id=UUID(str(existing["device_id"])),
            token_hash=token_hash,
            expires_at=expires_at,
        )
        return RegisterWorkerDeviceResponse(
            workerId=str(existing["worker_public_id"]),
            deviceId=str(existing["device_public_id"]),
            accessToken=access_token,
            expiresAt=expires_at,
        )

    async def _last_heartbeat_sequence(self, connection: AsyncConnection, device_id: UUID) -> int:
        value = (
            await connection.execute(
                text(
                    """
                    SELECT COALESCE(MAX(sequence_number), 0) AS last_sequence
                    FROM public.worker_heartbeats
                    WHERE worker_device_id = :device_id
                    """
                ),
                {"device_id": device_id},
            )
        ).scalar_one()
        return int(value)

    async def submit_benchmark_for_session(
        self,
        connection: AsyncConnection,
        *,
        session_token: str,
        worker_public_id: str,
        payload: SubmitBenchmarkRequest,
        idempotency_key: str,
        request_id: str | None = None,
    ) -> CommandReceipt:
        from edgemint.workers.sessions import resolve_worker_session

        session = await resolve_worker_session(
            connection,
            access_token=session_token,
            expected_worker_public_id=worker_public_id,
        )
        if not payload.signature:
            raise worker_error("INPUT_SCHEMA_INVALID", detail="signature required")

        tier = derive_device_tier(
            [{"metric": item.metric, "value": item.value} for item in payload.results]
        )
        await connection.execute(
            text(
                """
                INSERT INTO public.worker_benchmarks(
                    worker_device_id, benchmark_json, measured_at_utc
                )
                VALUES (
                    :worker_device_id,
                    CAST(:benchmark_json AS jsonb),
                    :measured_at_utc
                )
                """
            ),
            {
                "worker_device_id": session.device_id,
                "benchmark_json": json.dumps(payload.model_dump(mode="json")),
                "measured_at_utc": payload.measuredAt,
            },
        )
        await self.calibration.upsert_from_benchmark(
            connection,
            worker_device_id=session.device_id,
            payload=payload,
        )
        await connection.execute(
            text(
                """
                UPDATE public.worker_devices
                SET device_tier = :device_tier
                WHERE id = :device_id
                """
            ),
            {"device_id": session.device_id, "device_tier": tier},
        )
        if session.worker_status == "attesting":
            self.lifecycle.assert_transition("attesting", "benchmarking")
            await connection.execute(
                text("UPDATE public.workers SET status = 'benchmarking' WHERE id = :worker_id"),
                {"worker_id": session.worker_id},
            )
        self.lifecycle.assert_transition("benchmarking", "ready")
        await connection.execute(
            text("UPDATE public.workers SET status = 'ready' WHERE id = :worker_id"),
            {"worker_id": session.worker_id},
        )
        now = datetime.now(UTC)
        return CommandReceipt(
            operationId="submitBenchmark",
            accepted=True,
            status="ready",
            occurredAt=now,
            resourceId=worker_public_id,
            requestId=request_id,
        )

    async def get_worker_calibration(
        self,
        connection: AsyncConnection,
        *,
        session_token: str,
        worker_public_id: str,
    ) -> WorkerCalibrationProfileView:
        from edgemint.workers.sessions import resolve_worker_session

        session = await resolve_worker_session(
            connection,
            access_token=session_token,
            expected_worker_public_id=worker_public_id,
        )
        return await self.calibration.get_profile_for_session(
            connection,
            worker_device_id=session.device_id,
            worker_public_id=session.worker_public_id,
            device_public_id=session.device_public_id,
        )
