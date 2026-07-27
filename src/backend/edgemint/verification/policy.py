from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any


@dataclass(frozen=True, slots=True)
class VerificationPolicy:
    spec: dict[str, Any]
    path: Path

    @classmethod
    def load(cls, root: Path | None = None) -> VerificationPolicy:
        repo_root = root or Path(__file__).resolve().parents[4]
        path = repo_root / "dsl" / "policies" / "verification" / "default-v2.yaml"
        import yaml

        document = yaml.safe_load(path.read_text(encoding="utf-8"))
        return cls(spec=document["spec"], path=path)

    def profile(self, task_type: str) -> dict[str, Any]:
        profiles = self.spec.get("profiles", {})
        if task_type not in profiles:
            raise KeyError(task_type)
        return profiles[task_type]

    @property
    def maximum_automatic_retries(self) -> int:
        return int(self.spec.get("maximumAutomaticRetries", 2))

    @property
    def outcomes(self) -> list[str]:
        return list(self.spec.get("outcomes", []))

    @property
    def evidence_retention_days(self) -> int:
        return int(self.spec.get("evidenceRetentionDays", 365))


@lru_cache
def get_verification_policy() -> VerificationPolicy:
    return VerificationPolicy.load()
