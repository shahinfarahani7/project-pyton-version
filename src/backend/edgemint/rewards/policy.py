from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any

import yaml


@dataclass(frozen=True, slots=True)
class RewardPolicy:
    spec: dict[str, Any]
    path: Path

    @classmethod
    def load(cls, root: Path | None = None) -> RewardPolicy:
        repo_root = root or Path(__file__).resolve().parents[4]
        path = repo_root / "dsl" / "policies" / "rewards" / "worker-reward-v2.yaml"
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
        return cls(spec=document["spec"], path=path)

    def rule_for(self, task_type: str) -> dict[str, Any]:
        for rule in self.spec["rules"]:
            if rule["taskType"] == task_type:
                return rule
        raise KeyError(task_type)

    @property
    def unit(self) -> str:
        return str(self.spec["unit"])

    @property
    def version_label(self) -> str:
        metadata = yaml.safe_load(self.path.read_text(encoding="utf-8"))["metadata"]
        return f"{metadata['name']}@{metadata['version']}"


@lru_cache
def load_reward_policy() -> RewardPolicy:
    return RewardPolicy.load()
