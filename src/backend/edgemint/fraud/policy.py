from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any

import yaml


@dataclass(frozen=True, slots=True)
class FraudPolicy:
    spec: dict[str, Any]
    path: Path

    @classmethod
    def load(cls, root: Path | None = None) -> FraudPolicy:
        repo_root = root or Path(__file__).resolve().parents[4]
        path = repo_root / "dsl" / "policies" / "fraud" / "fraud-score-v2.yaml"
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
        return cls(spec=document["spec"], path=path)


@lru_cache
def load_fraud_policy() -> FraudPolicy:
    return FraudPolicy.load()
