from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from itertools import pairwise
from pathlib import Path
from typing import Any

import yaml

CENTI_PER_XP = 100
LEVEL_ORDER = ("bronze", "silver", "gold", "platinum")


@dataclass(frozen=True, slots=True)
class LevelThreshold:
    level_id: str
    min_centi_xp: int


@dataclass(frozen=True, slots=True)
class BoostTerms:
    bonus_bps: int
    duration_hours: int
    task_quota: int
    price_token_minor_units: int | None


@dataclass(frozen=True, slots=True)
class ContributionPolicy:
    version_label: str
    base_xp: int
    xp_per_accepted_minute: int
    processing_caps_ms: dict[str, int]
    levels: tuple[LevelThreshold, ...]
    boost: BoostTerms

    def cap_ms_for(self, task_type: str) -> int | None:
        return self.processing_caps_ms.get(task_type)

    @classmethod
    def from_document(cls, document: dict[str, Any]) -> ContributionPolicy:
        spec = document["spec"]
        metadata = document["metadata"]
        levels = tuple(
            LevelThreshold(level_id=str(item["id"]), min_centi_xp=int(item["minXp"]) * CENTI_PER_XP)
            for item in spec["levels"]
        )
        if tuple(level.level_id for level in levels) != LEVEL_ORDER:
            raise ValueError("contribution levels must be bronze, silver, gold, platinum in order")
        if levels[0].min_centi_xp != 0:
            raise ValueError("bronze must start at 0 XP")
        if any(a.min_centi_xp >= b.min_centi_xp for a, b in pairwise(levels)):
            raise ValueError("contribution level thresholds must strictly increase")
        boost = spec["boost"]
        price = boost.get("priceTokenMinorUnits")
        return cls(
            version_label=f"{metadata['name']}@{metadata['version']}",
            base_xp=int(spec["baseXp"]),
            xp_per_accepted_minute=int(spec["xpPerAcceptedMinute"]),
            processing_caps_ms={
                str(item["taskType"]): int(item["capMs"]) for item in spec["processingCapsMs"]
            },
            levels=levels,
            boost=BoostTerms(
                bonus_bps=int(boost["bonusBps"]),
                duration_hours=int(boost["durationHours"]),
                task_quota=int(boost["taskQuota"]),
                price_token_minor_units=None if price is None else int(price),
            ),
        )

    @classmethod
    def load(cls, root: Path | None = None) -> ContributionPolicy:
        repo_root = root or Path(__file__).resolve().parents[4]
        path = repo_root / "dsl" / "policies" / "contribution" / "worker-contribution-xp-v1.yaml"
        return cls.from_document(yaml.safe_load(path.read_text(encoding="utf-8")))


@lru_cache
def load_contribution_policy() -> ContributionPolicy:
    return ContributionPolicy.load()
