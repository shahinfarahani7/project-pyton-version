from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import yaml

from edgemint.tasks.errors import task_error

TERMINAL_DB_STATUSES = frozenset({"cancelled", "expired", "succeeded"})
CANCELLABLE_DB_STATUSES = frozenset({"draft", "submitted", "queued", "admitted", "assigned", "running"})
REVISION_ELIGIBLE_DB_STATUSES = frozenset({"failed"})


@dataclass(frozen=True, slots=True)
class TaskLifecycle:
    transitions: frozenset[tuple[str, str]]

    @classmethod
    def load(cls, path: Path | None = None) -> TaskLifecycle:
        workflow_path = path or (
            Path(__file__).resolve().parents[4] / "dsl" / "workflows" / "task-lifecycle.yaml"
        )
        document = yaml.safe_load(workflow_path.read_text(encoding="utf-8"))
        pairs = {
            (str(item["from"]), str(item["to"]))
            for item in document["spec"]["transitions"]
        }
        return cls(transitions=frozenset(pairs))

    def can_transition(self, current: str, target: str) -> bool:
        return (current, target) in self.transitions

    def assert_transition(self, current: str, target: str) -> None:
        if not self.can_transition(current, target):
            raise task_error("TASK_NOT_CANCELLABLE", detail=f"{current} -> {target} not allowed")


def map_db_lifecycle_to_api(db_status: str) -> str:
    if db_status in {"submitted", "queued", "admitted"}:
        return "submitted"
    if db_status in {"assigned", "running", "verifying"}:
        return "submitted"
    if db_status == "succeeded":
        return "completed"
    return db_status


def map_db_execution_status(db_status: str) -> str:
    if db_status in {"submitted", "queued", "admitted", "assigned", "running", "verifying"}:
        return "queued"
    if db_status == "succeeded":
        return "completed"
    if db_status == "failed":
        return "failed"
    if db_status == "cancelled":
        return "cancelled"
    if db_status == "expired":
        return "expired"
    return "queued"


def priority_mapping(priority: str) -> tuple[str, int]:
    table: dict[str, tuple[str, int]] = {
        "batch": ("batch", 1000),
        "standard": ("standard", 2000),
        "priority": ("high", 3000),
        "realtime": ("critical", 4000),
    }
    return table.get(priority, ("standard", 2000))


def task_type_to_catalog_code(api_task_type: str) -> str:
    return api_task_type.replace("-", ".")


def task_type_to_api_code(catalog_code: str) -> str:
    return catalog_code.replace(".", "-")
