from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from uuid import UUID

import yaml
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection


@dataclass(frozen=True, slots=True)
class ExclusiveGroupDefinition:
    group_id: str
    maximum_concurrent: int
    certified_maximum_concurrent: int | None
    execution_class: str
    runtime_classes: frozenset[str]
    device_exclusive: bool


@dataclass(frozen=True, slots=True)
class ExclusiveCrossGroupRule:
    group_a: str
    group_b: str
    concurrent_allowed: bool
    reason: str
    certification_required: bool


@dataclass(frozen=True, slots=True)
class ActiveExclusiveGroupPolicy:
    name: str
    version: str
    groups: dict[str, ExclusiveGroupDefinition]
    cross_group_rules: dict[frozenset[str], ExclusiveCrossGroupRule]
    light_work_groups: frozenset[str]


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


def _pair_key(group_a: str, group_b: str) -> frozenset[str]:
    return frozenset({group_a, group_b})


@lru_cache(maxsize=1)
def load_active_exclusive_group_policy() -> ActiveExclusiveGroupPolicy:
    policy_dir = _repo_root() / "dsl" / "policies" / "scheduling"
    active: ActiveExclusiveGroupPolicy | None = None
    for path in sorted(policy_dir.glob("*.yaml")):
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
        if document.get("kind") != "ExclusiveGroupPolicy":
            continue
        metadata = document["metadata"]
        if metadata.get("status") != "active":
            continue
        spec = document["spec"]
        groups: dict[str, ExclusiveGroupDefinition] = {}
        for item in spec["groups"]:
            group_id = str(item["id"])
            groups[group_id] = ExclusiveGroupDefinition(
                group_id=group_id,
                maximum_concurrent=int(item["maximumConcurrentReservationsPerDevice"]),
                certified_maximum_concurrent=item.get("certifiedMaximumConcurrentReservationsPerDevice"),
                execution_class=str(item["executionClass"]),
                runtime_classes=frozenset(item["runtimeClasses"]),
                device_exclusive=bool(item.get("deviceExclusive", False)),
            )
        cross_group_rules: dict[frozenset[str], ExclusiveCrossGroupRule] = {}
        for rule in spec["crossGroupRules"]:
            key = _pair_key(str(rule["groupA"]), str(rule["groupB"]))
            cross_group_rules[key] = ExclusiveCrossGroupRule(
                group_a=str(rule["groupA"]),
                group_b=str(rule["groupB"]),
                concurrent_allowed=bool(rule["concurrentAllowed"]),
                reason=str(rule["reason"]),
                certification_required=bool(rule.get("certificationRequired", False)),
            )
        candidate = ActiveExclusiveGroupPolicy(
            name=str(metadata["name"]),
            version=str(metadata["version"]),
            groups=groups,
            cross_group_rules=cross_group_rules,
            light_work_groups=frozenset(spec["lightWorkGroups"]),
        )
        if active is not None:
            raise ValueError("multiple active ExclusiveGroupPolicy documents")
        active = candidate
    if active is None:
        raise ValueError("no active ExclusiveGroupPolicy document")
    return active


def _thermal_exclusive_limit(limit: int, thermal_state: str | None) -> int:
    if thermal_state in {"serious", "critical"}:
        return 1
    if thermal_state == "fair":
        return max(1, limit // 2)
    return limit


def exclusive_group_enforcement_reasons(
    *,
    requested_group: str,
    active_counts: dict[str, int],
    device_certified: bool = False,
    thermal_state: str | None = None,
    profile: ActiveExclusiveGroupPolicy | None = None,
) -> list[str]:
    if not requested_group:
        return []
    active_profile = profile or load_active_exclusive_group_policy()
    group = active_profile.groups.get(requested_group)
    if group is None:
        return ["EXCLUSIVE_GROUP_UNKNOWN"]

    limit = group.maximum_concurrent
    if device_certified and group.certified_maximum_concurrent is not None:
        limit = group.certified_maximum_concurrent
    limit = _thermal_exclusive_limit(limit, thermal_state)
    if active_counts.get(requested_group, 0) >= limit:
        return ["EXCLUSIVE_GROUP_SATURATED"]

    for active_group, count in active_counts.items():
        if count <= 0 or active_group == requested_group:
            continue
        rule = active_profile.cross_group_rules.get(_pair_key(active_group, requested_group))
        if rule is None or rule.concurrent_allowed:
            continue
        if rule.certification_required and device_certified:
            continue
        return ["EXCLUSIVE_GROUP_CROSS_BLOCKED"]

    return []


async def load_device_exclusive_group_counts(
    connection: AsyncConnection,
    *,
    worker_device_id: UUID,
) -> dict[str, int]:
    rows = (
        await connection.execute(
            text(
                """
                SELECT exclusive_group, COUNT(*) AS reservation_count
                FROM public.worker_resource_reservations
                WHERE worker_device_id = :worker_device_id
                  AND exclusive_group <> ''
                  AND (
                    status IN ('reserved', 'active')
                    OR (
                      status IN ('released', 'expired', 'revoked')
                      AND physical_release_state IN ('held', 'stop_requested', 'unknown')
                    )
                  )
                GROUP BY exclusive_group
                """
            ),
            {"worker_device_id": worker_device_id},
        )
    ).mappings()
    return {str(row["exclusive_group"]): int(row["reservation_count"]) for row in rows}


def can_reserve_exclusive_group(
    *,
    requested_group: str,
    active_counts: dict[str, int],
    device_certified: bool = False,
    thermal_state: str | None = None,
) -> bool:
    return not exclusive_group_enforcement_reasons(
        requested_group=requested_group,
        active_counts=active_counts,
        device_certified=device_certified,
        thermal_state=thermal_state,
    )
