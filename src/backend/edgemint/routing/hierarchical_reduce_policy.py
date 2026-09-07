from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from functools import lru_cache
from pathlib import Path

import yaml


class ReduceProgressRule(StrEnum):
    GROUPS_OR_TOKEN_MASS_MUST_DECREASE = "groups_or_token_mass_must_decrease"


@dataclass(frozen=True, slots=True)
class HierarchicalReduceBounds:
    max_chunks: int
    max_reduce_depth: int
    max_inference_calls: int
    max_output_tokens_per_stage: int
    min_token_mass_reduction_ratio_milli: int
    progress_rule: ReduceProgressRule


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


@lru_cache(maxsize=1)
def _load_bounds_by_plan() -> dict[str, HierarchicalReduceBounds]:
    plan_dir = _repo_root() / "dsl" / "catalog" / "execution-plans"
    bounds: dict[str, HierarchicalReduceBounds] = {}
    for path in sorted(plan_dir.glob("*.yaml")):
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
        metadata = document["metadata"]
        spec = document.get("spec") or {}
        raw = spec.get("reduceBounds")
        if not raw:
            continue
        bounds[str(metadata["name"])] = HierarchicalReduceBounds(
            max_chunks=int(raw["maxChunks"]),
            max_reduce_depth=int(raw["maxReduceDepth"]),
            max_inference_calls=int(raw["maxInferenceCalls"]),
            max_output_tokens_per_stage=int(raw["maxOutputTokensPerStage"]),
            min_token_mass_reduction_ratio_milli=int(raw["minTokenMassReductionRatioMilli"]),
            progress_rule=ReduceProgressRule(str(raw["progressRule"])),
        )
    return bounds


def reduce_bounds_for_plan(plan_name: str) -> HierarchicalReduceBounds | None:
    return _load_bounds_by_plan().get(plan_name)


def default_text_summarize_reduce_bounds() -> HierarchicalReduceBounds:
    bounds = reduce_bounds_for_plan("text-summarize-map-reduce")
    if bounds is None:
        raise RuntimeError("text-summarize-map-reduce bounds missing from DSL")
    return bounds


def estimate_token_mass(payload: object) -> int:
    import json

    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return max(1, len(encoded) // 4)


def made_reduce_progress(
    *,
    before_groups: int,
    after_groups: int,
    before_token_mass: int,
    after_token_mass: int,
    min_token_mass_reduction_ratio_milli: int,
) -> bool:
    if after_groups < before_groups:
        return True
    if after_token_mass >= before_token_mass:
        return False
    if before_token_mass <= 0:
        return after_token_mass < before_token_mass
    reduction_milli = ((before_token_mass - after_token_mass) * 1000) // before_token_mass
    return reduction_milli >= min_token_mass_reduction_ratio_milli


def classify_reduce_exhaustion(
    *,
    depth: int,
    inference_calls: int,
    bounds: HierarchicalReduceBounds,
    chunk_count: int,
) -> str | None:
    if chunk_count > bounds.max_chunks:
        return "chunk_cap_exceeded"
    if depth >= bounds.max_reduce_depth:
        return "max_reduce_depth_exceeded"
    if inference_calls >= bounds.max_inference_calls:
        return "max_inference_calls_exceeded"
    return None
