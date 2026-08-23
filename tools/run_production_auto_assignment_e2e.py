#!/usr/bin/env python3
from __future__ import annotations

import asyncio
import importlib.util
import json
import os
import secrets
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import uuid4


ROOT = Path(__file__).resolve().parents[1]


def blocked_reasons() -> list[str]:
    reasons: list[str] = []
    if importlib.util.find_spec("sqlalchemy") is None:
        reasons.append("sqlalchemy runtime is not installed")
    if importlib.util.find_spec("psycopg") is None:
        reasons.append("psycopg runtime is not installed")
    if not os.environ.get("EDGEMINT_DATABASE_URL"):
        reasons.append("EDGEMINT_DATABASE_URL is not configured")
    if not os.environ.get("EDGEMINT_LEASE_CREDENTIAL_ENCRYPTION_KEY"):
        reasons.append("EDGEMINT_LEASE_CREDENTIAL_ENCRYPTION_KEY is not configured")
    return reasons


async def run() -> dict[str, object]:
    sys.path.insert(0, str(ROOT / "src" / "backend"))
    from sqlalchemy import text
    from sqlalchemy.ext.asyncio import create_async_engine

    from edgemint.building_blocks.settings import get_settings
    from edgemint.routing.service import RouterService
    from edgemint.security.tokens import hash_session_token
    from edgemint.workers.assignments import (
        AssignmentCommandService,
        AssignmentCredentialBootstrapService,
    )

    get_settings.cache_clear()
    settings = get_settings()
    engine = create_async_engine(settings.require_database_url(), pool_pre_ping=True)
    evidence: dict[str, object] = {}
    async with engine.connect() as connection:
        transaction = await connection.begin()
        try:
            organization_id = uuid4()
            workspace_id = uuid4()
            principal_id = uuid4()
            worker_id = uuid4()
            device_id = uuid4()
            task_id = uuid4()
            revision_id = uuid4()
            attempt_id = uuid4()
            access_token = secrets.token_urlsafe(48)
            router_owner = f"e2e-router-{uuid4()}"
            now = datetime.now(UTC)

            await connection.execute(
                text("SELECT set_config('app.workspace_id', :workspace_id, true)"),
                {"workspace_id": str(workspace_id)},
            )
            seed_parameters = {
                    "id": organization_id,
                    "public_id": f"org_{secrets.token_hex(13).upper()[:26]}",
                    "workspace_id": workspace_id,
                    "organization_id": organization_id,
                    "workspace_public_id": f"ws_{secrets.token_hex(13).upper()[:26]}",
                    "principal_id": principal_id,
                    "subject": f"e2e-worker:{device_id}",
                    "worker_id": worker_id,
                    "worker_public_id": f"wrk_{secrets.token_hex(13).upper()[:26]}",
                    "device_id": device_id,
                    "device_public_id": f"dev_{secrets.token_hex(13).upper()[:26]}",
                    "attestation_expiry": now + timedelta(hours=1),
                    "installation_id": f"e2e-{device_id}",
                    "fingerprint": secrets.token_hex(32),
                    "policy_version": settings.worker_consent_policy_version,
                    "now": now,
                    "session_token_hash": hash_session_token(access_token),
                    "session_expiry": now + timedelta(hours=1),
                    "task_id": task_id,
                    "task_public_id": f"task_{secrets.token_hex(13).upper()[:26]}",
                    "task_idempotency": f"e2e-{task_id}",
                    "revision_id": revision_id,
                    "attempt_id": attempt_id,
                    "router_owner": router_owner,
                    "routing_expiry": now + timedelta(minutes=1),
            }
            seed_statements = [
                "INSERT INTO public.organizations(id, public_id, name, status) "
                "VALUES (:id, :public_id, 'Lease E2E', 'active')",
                "INSERT INTO public.workspaces(id, organization_id, public_id, name, status, data_region) "
                "VALUES (:workspace_id, :organization_id, :workspace_public_id, "
                "'Lease E2E', 'active', 'eu')",
                "INSERT INTO public.principals(id, subject, principal_type, display_name) "
                "VALUES (:principal_id, :subject, 'worker', 'Lease E2E Worker')",
                "INSERT INTO public.workers(id, principal_id, public_id, status, trust_bps, reliability_bps) "
                "VALUES (:worker_id, :principal_id, :worker_public_id, 'active', 9000, 9000)",
                """INSERT INTO public.worker_devices(
                    id, worker_id, public_id, platform, app_version, runtime_abi, region_code,
                    device_tier, attestation_status, attestation_expires_at_utc, status,
                    installation_id, public_key_fingerprint
                ) VALUES (
                    :device_id, :worker_id, :device_public_id, 'android', '5.0.0', 'any', 'FI',
                    'T2', 'verified', :attestation_expiry, 'active', :installation_id, :fingerprint
                )""",
                "INSERT INTO public.worker_consents(worker_id, policy_version, accepted_at_utc) "
                "VALUES (:worker_id, :policy_version, :now)",
                """INSERT INTO public.worker_preferences(
                    worker_id, availability, network_policy, charging_policy,
                    minimum_battery_percent, schedule_json, schedule_mode
                ) VALUES (
                    :worker_id, 'available', 'wifi_only', 'not_required', 25, '{}'::jsonb, 'always'
                )""",
                """INSERT INTO public.worker_heartbeats(
                    worker_device_id, sequence_number, observed_at_utc, battery_bps, charging,
                    thermal_state, free_ram_bytes, free_storage_bytes, network_type,
                    current_leases_json, installed_models_json, received_at_utc
                ) VALUES (
                    :device_id, 1, :now, 9000, true, 'nominal', 4294967296, 8589934592,
                    'wifi', '[]'::jsonb, '[]'::jsonb, :now
                )""",
                "INSERT INTO public.worker_sessions(worker_device_id, session_token_hash, expires_at_utc) "
                "VALUES (:device_id, :session_token_hash, :session_expiry)",
                """INSERT INTO public.tasks(
                    id, workspace_id, public_id, task_type, lifecycle_status,
                    idempotency_key, priority_class, priority_bps, submitted_at_utc
                ) VALUES (
                    :task_id, :workspace_id, :task_public_id, 'document.ocr', 'queued',
                    :task_idempotency, 'standard', 2000, :now
                )""",
                """INSERT INTO public.task_revisions(
                    id, workspace_id, task_id, revision_number, inline_text, parameters_json,
                    required_device_tier, required_runtime_abi, minimum_free_ram_bytes,
                    minimum_free_storage_bytes, allowed_worker_regions_json, submitted_at_utc
                ) VALUES (
                    :revision_id, :workspace_id, :task_id, 1, 'Production lease E2E', '{}'::jsonb,
                    'T1', 'any', 0, 0, '["*"]'::jsonb, :now
                )""",
                "UPDATE public.tasks SET current_revision_id = :revision_id WHERE id = :task_id",
                """INSERT INTO public.task_attempts(
                    id, workspace_id, task_id, attempt_number, status,
                    routing_claim_owner, routing_claim_expires_at_utc
                ) VALUES (
                    :attempt_id, :workspace_id, :task_id, 1, 'matching',
                    :router_owner, :routing_expiry
                )""",
            ]
            for statement in seed_statements:
                await connection.execute(text(statement), seed_parameters)

            lease = await RouterService(settings=settings).acquire_assignment_lease(
                connection,
                task_attempt_id=attempt_id,
                worker_id=worker_id,
                worker_device_id=device_id,
                router_instance_id=router_owner,
            )
            bootstrap = await AssignmentCredentialBootstrapService(settings=settings).next_assignment(
                connection,
                access_token=access_token,
            )
            if bootstrap is None or bootstrap["leaseToken"] != lease["leaseToken"]:
                raise AssertionError("bootstrap did not recover the Router lease credential")
            commands = AssignmentCommandService(settings=settings)
            await commands.start(
                connection,
                access_token=access_token,
                assignment_id=lease["assignmentId"],
                lease_token=bootstrap["leaseToken"],
                fence_token=bootstrap["fenceToken"],
            )
            renewal = await commands.renew(
                connection,
                access_token=access_token,
                assignment_id=lease["assignmentId"],
                lease_token=bootstrap["leaseToken"],
                fence_token=bootstrap["fenceToken"],
                sequence=1,
            )
            state = (
                await connection.execute(
                    text(
                        """
                        SELECT assignment.status, attempt.status AS attempt_status,
                               task.lifecycle_status AS task_status,
                               assignment.last_renewal_sequence,
                               count(event.id) FILTER (
                                 WHERE event.event_type IN (
                                   'assignment.leased', 'assignment.started', 'assignment.lease_renewed'
                                 )
                               ) AS lifecycle_event_count
                        FROM public.assignments AS assignment
                        JOIN public.task_attempts AS attempt ON attempt.id = assignment.task_attempt_id
                        JOIN public.tasks AS task ON task.id = attempt.task_id
                        LEFT JOIN public.outbox_events AS event
                          ON event.aggregate_type = 'assignment'
                         AND event.aggregate_id = assignment.id::text
                        WHERE assignment.id = :assignment_id
                        GROUP BY assignment.status, attempt.status, task.lifecycle_status,
                                 assignment.last_renewal_sequence
                        """
                    ),
                    {"assignment_id": lease["assignmentId"]},
                )
            ).mappings().one()
            assert state["status"] == "running"
            assert state["attempt_status"] == "running"
            assert state["task_status"] == "running"
            assert int(state["last_renewal_sequence"]) == 1
            assert int(state["lifecycle_event_count"]) == 3
            evidence = {
                "status": "passed",
                "assignmentId": lease["assignmentId"],
                "fenceToken": lease["fenceToken"],
                "bootstrapCredentialMatched": True,
                "assignmentStatus": state["status"],
                "attemptStatus": state["attempt_status"],
                "taskStatus": state["task_status"],
                "renewalSequence": int(state["last_renewal_sequence"]),
                "outboxLifecycleEvents": int(state["lifecycle_event_count"]),
                "renewedUntil": renewal["leaseExpiresAt"],
                "transactionRolledBackAfterVerification": True,
            }
        finally:
            await transaction.rollback()
    await engine.dispose()
    return evidence


def main() -> int:
    reasons = blocked_reasons()
    if reasons:
        print(
            json.dumps(
                {
                    "status": "blocked",
                    "test": "production-auto-assignment-e2e",
                    "reasons": reasons,
                },
                indent=2,
            )
        )
        return 2
    try:
        print(json.dumps(asyncio.run(run()), indent=2))
        return 0
    except Exception as exc:
        print(
            json.dumps(
                {
                    "status": "failed",
                    "test": "production-auto-assignment-e2e",
                    "errorType": type(exc).__name__,
                    "error": str(exc),
                },
                indent=2,
            )
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
