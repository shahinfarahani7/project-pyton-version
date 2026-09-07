from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any

import yaml

from edgemint.routing.checkpoint_policy_matrix import get_checkpoint_policy_matrix

_LONG_CONTEXT_TOKEN_THRESHOLD = 4000


@dataclass(frozen=True, slots=True)
class ExecutionStage:
    sequence: int
    name: str
    operation: str
    runtime_class: str
    checkpoint_enabled: bool
    estimated_duration_ms: int
    required_model_ids: tuple[str, ...] = ()
    retry_policy: str = "none"
    validation_rule: str | None = None
    exclusive_group: str | None = None


@dataclass(frozen=True, slots=True)
class ExecutionPlan:
    task_type: str
    plan_name: str
    plan_version: str
    input_mode: str | None
    stages: tuple[ExecutionStage, ...]

    def as_dict(self) -> dict[str, Any]:
        return {
            "taskType": self.task_type,
            "planName": self.plan_name,
            "planVersion": self.plan_version,
            "inputMode": self.input_mode,
            "stageCount": len(self.stages),
            "stages": [
                {
                    "sequence": stage.sequence,
                    "name": stage.name,
                    "operation": stage.operation,
                    "runtimeClass": stage.runtime_class,
                    "requiredModelIds": list(stage.required_model_ids),
                    "checkpointEnabled": stage.checkpoint_enabled,
                    "retryPolicy": stage.retry_policy,
                    "validationRule": stage.validation_rule,
                    "estimatedDurationMs": stage.estimated_duration_ms,
                    "exclusiveGroup": stage.exclusive_group,
                }
                for stage in self.stages
            ],
        }


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


def _parse_plan(document: dict[str, Any]) -> ExecutionPlan:
    metadata = document["metadata"]
    spec = document["spec"]
    stages = tuple(
        ExecutionStage(
            sequence=int(stage["sequence"]),
            name=str(stage["name"]),
            operation=str(stage["operation"]),
            runtime_class=str(stage["runtimeClass"]),
            checkpoint_enabled=bool(stage["checkpointEnabled"]),
            estimated_duration_ms=int(stage["estimatedDurationMs"]),
            required_model_ids=tuple(stage.get("requiredModelIds") or ()),
            retry_policy=str(stage.get("retryPolicy") or "none"),
            validation_rule=stage.get("validationRule"),
            exclusive_group=stage.get("exclusiveGroup"),
        )
        for stage in spec["stages"]
    )
    return ExecutionPlan(
        task_type=str(spec["taskType"]),
        plan_name=str(metadata["name"]),
        plan_version=str(spec.get("planVersion") or metadata["version"]),
        input_mode=str(spec["inputMode"]) if spec.get("inputMode") else None,
        stages=stages,
    )


@lru_cache(maxsize=1)
def _load_plan_catalog() -> dict[str, ExecutionPlan]:
    plan_dir = _repo_root() / "dsl" / "catalog" / "execution-plans"
    catalog: dict[str, ExecutionPlan] = {}
    for path in sorted(plan_dir.glob("*.yaml")):
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
        plan = _parse_plan(document)
        catalog[plan.plan_name] = plan
    return catalog


def plan_by_name(name: str) -> ExecutionPlan | None:
    return _load_plan_catalog().get(name)


def resolve_execution_plan(
    *,
    task_type: str,
    estimated_input_tokens: int = 0,
    page_count: int = 0,
) -> ExecutionPlan:
    """Select server-approved execution plan from task type and input hints."""
    if task_type == "text.summarize":
        if estimated_input_tokens >= _LONG_CONTEXT_TOKEN_THRESHOLD:
            plan = plan_by_name("text-summarize-map-reduce")
        else:
            plan = plan_by_name("text-summarize-direct")
        if plan is not None:
            return plan
    if task_type == "document.summarize" or (task_type == "document.extract" and page_count > 1):
        plan = plan_by_name("document-summarize")
        if plan is not None:
            return plan
    if task_type in {"document.ocr", "ocr.receipt", "ocr.invoice"}:
        checkpoint_enabled = get_checkpoint_policy_matrix().checkpoint_enabled_for(task_type)
        return ExecutionPlan(
            task_type=task_type,
            plan_name="inline-ocr",
            plan_version="2026-q3-v1",
            input_mode="document",
            stages=(
                ExecutionStage(
                    sequence=1,
                    name="ocr",
                    operation="ocr",
                    runtime_class="paddle_ocr",
                    checkpoint_enabled=checkpoint_enabled,
                    estimated_duration_ms=90_000,
                    required_model_ids=("paddleocr-mobile",),
                    retry_policy="stage_with_backoff",
                    exclusive_group="ocr_inference",
                ),
                ExecutionStage(
                    sequence=2,
                    name="submit",
                    operation="submit",
                    runtime_class="network_io",
                    checkpoint_enabled=False,
                    estimated_duration_ms=3_000,
                    retry_policy="stage_once",
                ),
            ),
        )
    checkpoint_enabled = get_checkpoint_policy_matrix().checkpoint_enabled_for(task_type)
    return ExecutionPlan(
        task_type=task_type,
        plan_name="inline-single-shot",
        plan_version="2026-q3-v1",
        input_mode=None,
        stages=(
            ExecutionStage(
                sequence=1,
                name="execute",
                operation="execute",
                runtime_class="system",
                checkpoint_enabled=checkpoint_enabled,
                estimated_duration_ms=60_000,
                retry_policy="stage_once",
            ),
            ExecutionStage(
                sequence=2,
                name="submit",
                operation="submit",
                runtime_class="network_io",
                checkpoint_enabled=False,
                estimated_duration_ms=3_000,
                retry_policy="stage_once",
            ),
        ),
    )
