"""Operational activation gate wiring for admission and dispatch."""

from __future__ import annotations

import json
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.building_blocks.settings import Settings, get_settings
from edgemint.governance.policy_readiness_gate import (
    PolicyCompatibility,
    PolicyReadinessRecord,
    evaluate_activation_gate,
    evaluate_policy_area,
    load_policy_readiness_gate,
)
from edgemint.routing.errors import router_error
from edgemint.tasks.errors import task_error


def _configured_policy_areas() -> list:
    gate = load_policy_readiness_gate()
    areas: list = []
    for area_name, values in (gate.get("policyAreas") or {}).items():
        if not isinstance(values, dict):
            continue
        configured = [key for key, value in values.items() if value not in (None, "", [])]
        missing = [key for key, value in values.items() if value in (None, "", [])]
        areas.append(
            evaluate_policy_area(
                area=str(area_name),
                configured_values=[str(item) for item in configured],
                missing_values=[str(item) for item in missing],
                policy=gate,
            )
        )
    if areas:
        return areas

    routing = gate.get("routing") or {}
    timeouts = routing.get("timeouts") or {}
    configured = [f"{key}={value}" for key, value in sorted(timeouts.items()) if value is not None]
    return [
        evaluate_policy_area(
            area="execution_grant",
            configured_values=configured,
            missing_values=[],
            policy=gate,
        )
    ]


async def load_open_policy_readiness_record(
    connection: AsyncConnection,
) -> PolicyReadinessRecord | None:
    row = (
        await connection.execute(
            text(
                """
                SELECT architecture_version,
                       policy_version_hash,
                       runtime_profile_scope,
                       responsible_owner,
                       values_json,
                       evidence_json,
                       compatibility_json,
                       feature_flags_json
                FROM public.policy_readiness_records
                WHERE activation_status = 'open'
                ORDER BY updated_at_utc DESC
                LIMIT 1
                """
            )
        )
    ).mappings().first()
    if row is None:
        return None

    compatibility_raw = row["compatibility_json"]
    if isinstance(compatibility_raw, str):
        compatibility_raw = json.loads(compatibility_raw)
    if not isinstance(compatibility_raw, dict):
        compatibility_raw = {}

    values_raw = row["values_json"]
    if isinstance(values_raw, str):
        values_raw = json.loads(values_raw)
    if not isinstance(values_raw, dict):
        values_raw = {}

    evidence_raw = row["evidence_json"]
    if isinstance(evidence_raw, str):
        evidence_raw = json.loads(evidence_raw)
    evidence = [str(item) for item in evidence_raw] if isinstance(evidence_raw, list) else []

    flags_raw = row["feature_flags_json"]
    if isinstance(flags_raw, str):
        flags_raw = json.loads(flags_raw)
    feature_flags = (
        {str(key): bool(value) for key, value in flags_raw.items()}
        if isinstance(flags_raw, dict)
        else {}
    )

    return PolicyReadinessRecord(
        architectureVersion=str(row["architecture_version"]),
        policyVersionHash=str(row["policy_version_hash"]),
        runtimeProfileScope=str(row["runtime_profile_scope"]),
        responsibleOwner=str(row["responsible_owner"]),
        values=values_raw,
        evidence=evidence,
        compatibility=PolicyCompatibility(
            workerAppMinBuild=int(compatibility_raw.get("workerAppMinBuild", 1)),
            workerAppMaxBuild=(
                int(compatibility_raw["workerAppMaxBuild"])
                if compatibility_raw.get("workerAppMaxBuild") is not None
                else None
            ),
        ),
        featureFlags=feature_flags,
    )


def activation_gate_enforced(settings: Settings | None = None) -> bool:
    active = settings or get_settings()
    return active.environment in {"staging", "production"}


async def evaluate_runtime_activation_gate(
    connection: AsyncConnection,
    *,
    settings: Settings | None = None,
) -> dict[str, Any]:
    active = settings or get_settings()
    if not activation_gate_enforced(active):
        return {"status": "OPEN", "reason": "activation_gate_not_enforced", "blockedAreas": []}

    record = await load_open_policy_readiness_record(connection)
    result = evaluate_activation_gate(policy_areas=_configured_policy_areas(), record=record)
    return {
        "status": result.status,
        "reason": result.reason,
        "blockedAreas": list(result.blocked_areas),
    }


async def assert_runtime_activation_gate_open(
    connection: AsyncConnection,
    *,
    settings: Settings | None = None,
) -> None:
    payload = await evaluate_runtime_activation_gate(connection, settings=settings)
    if payload["status"] != "OPEN":
        raise router_error(
            "POLICY_READINESS_BLOCKED",
            detail=str(payload["reason"]),
        )


async def assert_admission_activation_gate_open(
    connection: AsyncConnection,
    *,
    settings: Settings | None = None,
) -> None:
    payload = await evaluate_runtime_activation_gate(connection, settings=settings)
    if payload["status"] != "OPEN":
        raise task_error(
            "POLICY_READINESS_BLOCKED",
            detail=str(payload["reason"]),
        )
