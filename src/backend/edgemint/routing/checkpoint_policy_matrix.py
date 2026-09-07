from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any


@dataclass(frozen=True, slots=True)
class TaskCheckpointPolicy:
    task_type: str
    checkpoint_enabled: bool
    checkpoint_strategy: str
    maximum_interval_seconds: int


@dataclass(frozen=True, slots=True)
class CheckpointPolicyMatrix:
    spec: dict[str, Any]
    path: Path
    entries: dict[str, TaskCheckpointPolicy]

    @classmethod
    def load(cls, root: Path | None = None) -> CheckpointPolicyMatrix:
        repo_root = root or Path(__file__).resolve().parents[4]
        path = repo_root / "dsl" / "policies" / "checkpoints" / "task-checkpoint-matrix-v1.yaml"
        import yaml

        document = yaml.safe_load(path.read_text(encoding="utf-8"))
        spec = document["spec"]
        return cls(spec=spec, path=path, entries=_build_index(spec))

    @property
    def default_maximum_interval_seconds(self) -> int:
        return int(self.spec.get("defaultMaximumIntervalSeconds", 60))

    def entry(self, task_type: str) -> TaskCheckpointPolicy | None:
        return self.entries.get(task_type)

    def checkpoint_enabled_for(self, task_type: str) -> bool:
        policy = self.entry(task_type)
        return bool(policy and policy.checkpoint_enabled)


def _build_index(spec: dict[str, Any]) -> dict[str, TaskCheckpointPolicy]:
    default_interval = int(spec.get("defaultMaximumIntervalSeconds", 60))
    index: dict[str, TaskCheckpointPolicy] = {}
    for row in spec.get("entries", []):
        task_type = str(row["taskType"])
        index[task_type] = TaskCheckpointPolicy(
            task_type=task_type,
            checkpoint_enabled=bool(row["checkpointEnabled"]),
            checkpoint_strategy=str(row["checkpointStrategy"]),
            maximum_interval_seconds=int(row.get("maximumIntervalSeconds", default_interval)),
        )
    return index


@lru_cache
def get_checkpoint_policy_matrix() -> CheckpointPolicyMatrix:
    return CheckpointPolicyMatrix.load()


def catalog_task_types(root: Path | None = None) -> list[str]:
    repo_root = root or Path(__file__).resolve().parents[4]
    import json

    catalog = json.loads((repo_root / "src" / "shared" / "task-types" / "catalog.json").read_text(encoding="utf-8"))
    return [
        str(item["value"])
        for category in catalog["categories"]
        for item in category["types"]
    ]
