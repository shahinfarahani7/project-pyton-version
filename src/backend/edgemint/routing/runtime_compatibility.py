from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

import yaml

_DEVICE_TIER_ORDER = {"T1": 1, "T2": 2, "T3": 3, "T4": 4}


@dataclass(frozen=True, slots=True)
class TaskRuntimeRequirement:
    task_runtime_class: str
    required_worker_runtime_classes: frozenset[str]
    minimum_device_tier: str | None


@dataclass(frozen=True, slots=True)
class CoRunRule:
    runtime_a: str
    runtime_b: str
    co_run_allowed: bool


@dataclass(frozen=True, slots=True)
class ActiveRuntimeCompatibilityProfile:
    name: str
    version: str
    task_requirements: dict[str, TaskRuntimeRequirement]
    co_run_rules: dict[frozenset[str], CoRunRule]


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


def _pair_key(runtime_a: str, runtime_b: str) -> frozenset[str]:
    return frozenset({runtime_a, runtime_b})


@lru_cache(maxsize=1)
def load_active_runtime_compatibility_profile() -> ActiveRuntimeCompatibilityProfile:
    profile_dir = _repo_root() / "dsl" / "catalog" / "runtime-compatibility"
    active: ActiveRuntimeCompatibilityProfile | None = None
    for path in sorted(profile_dir.glob("*.yaml")):
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
        if document.get("kind") != "RuntimeCompatibilityProfile":
            continue
        metadata = document["metadata"]
        if metadata.get("status") != "active":
            continue
        spec = document["spec"]
        task_requirements: dict[str, TaskRuntimeRequirement] = {}
        for item in spec["taskRequirements"]:
            task_requirements[str(item["taskRuntimeClass"])] = TaskRuntimeRequirement(
                task_runtime_class=str(item["taskRuntimeClass"]),
                required_worker_runtime_classes=frozenset(item["requiredWorkerRuntimeClasses"]),
                minimum_device_tier=item.get("minimumDeviceTier"),
            )
        co_run_rules: dict[frozenset[str], CoRunRule] = {}
        for rule in spec["coRunRules"]:
            key = _pair_key(str(rule["runtimeA"]), str(rule["runtimeB"]))
            co_run_rules[key] = CoRunRule(
                runtime_a=str(rule["runtimeA"]),
                runtime_b=str(rule["runtimeB"]),
                co_run_allowed=bool(rule["coRunAllowed"]),
            )
        candidate = ActiveRuntimeCompatibilityProfile(
            name=str(metadata["name"]),
            version=str(metadata["version"]),
            task_requirements=task_requirements,
            co_run_rules=co_run_rules,
        )
        if active is not None:
            raise ValueError("multiple active RuntimeCompatibilityProfile documents")
        active = candidate
    if active is None:
        raise ValueError("no active RuntimeCompatibilityProfile document")
    return active


def task_runtime_class_for_task_type(task_type: str) -> str | None:
    from edgemint.routing.envelope_registry import envelope_for_task_type

    envelope = envelope_for_task_type(task_type)
    if envelope is None:
        return None
    return envelope.runtime_class


def _device_tier_meets_minimum(device_tier: str | None, minimum_tier: str | None) -> bool:
    if minimum_tier is None:
        return True
    if device_tier is None:
        return False
    return _DEVICE_TIER_ORDER.get(device_tier, 0) >= _DEVICE_TIER_ORDER.get(minimum_tier, 0)


def runtime_incompatibility_reasons(
    *,
    worker_runtime_classes: list[str],
    task_runtime_class: str,
    device_tier: str | None = None,
    active_runtime_classes: list[str] | None = None,
    concurrency_certified: bool = False,
    profile: ActiveRuntimeCompatibilityProfile | None = None,
) -> list[str]:
    """Return hard-filter ineligibility reasons for worker/task runtime pairing."""
    active_profile = profile or load_active_runtime_compatibility_profile()
    worker_classes = set(worker_runtime_classes)
    reasons: list[str] = []

    requirement = active_profile.task_requirements.get(task_runtime_class)
    if requirement is None:
        reasons.append("RUNTIME_CLASS_UNKNOWN")
        return reasons

    if not requirement.required_worker_runtime_classes.issubset(worker_classes):
        reasons.append("RUNTIME_INCOMPATIBLE")

    if not _device_tier_meets_minimum(device_tier, requirement.minimum_device_tier):
        reasons.append("DEVICE_TIER_TOO_LOW")

    if active_runtime_classes:
        active = set(active_runtime_classes)
        for active_class in active:
            if active_class == task_runtime_class:
                continue
            rule = active_profile.co_run_rules.get(_pair_key(active_class, task_runtime_class))
            if rule is not None and not rule.co_run_allowed:
                if concurrency_certified and {active_class, task_runtime_class} == {
                    "mediapipe_llm",
                    "paddle_ocr",
                }:
                    continue
                reasons.append("RUNTIME_CO_RUN_BLOCKED")
                break

    return reasons


def is_runtime_compatible(
    *,
    worker_runtime_classes: list[str],
    task_runtime_class: str,
    device_tier: str | None = None,
    active_runtime_classes: list[str] | None = None,
    concurrency_certified: bool = False,
) -> bool:
    return not runtime_incompatibility_reasons(
        worker_runtime_classes=worker_runtime_classes,
        task_runtime_class=task_runtime_class,
        device_tier=device_tier,
        active_runtime_classes=active_runtime_classes,
        concurrency_certified=concurrency_certified,
    )
