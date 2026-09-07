from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from functools import lru_cache
from pathlib import Path

import yaml


@dataclass(frozen=True, slots=True)
class ContextProfileSpec:
    name: str
    version: str
    model_version_id: str
    verified_artifact_context_limit: int
    configured_runtime_context_limit: int
    system_template_tokens: int
    input_budget_tokens: int
    output_reserve_tokens: int
    safety_margin_tokens: int
    characters_per_token: float
    requires_formatted_prompt_count: bool
    enforce_max_output_tokens: bool


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


@lru_cache(maxsize=1)
def _load_context_profiles() -> dict[str, ContextProfileSpec]:
    profile_dir = _repo_root() / "dsl" / "catalog" / "context-profiles"
    profiles: dict[str, ContextProfileSpec] = {}
    for path in sorted(profile_dir.glob("*.yaml")):
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
        metadata = document["metadata"]
        spec = document["spec"]
        split = spec["budgetSplit"]
        key = f"{metadata['name']}@{metadata['version']}"
        profiles[key] = ContextProfileSpec(
            name=str(metadata["name"]),
            version=str(metadata["version"]),
            model_version_id=str(spec["modelVersionId"]),
            verified_artifact_context_limit=int(spec["verifiedArtifactContextLimit"]),
            configured_runtime_context_limit=int(spec["configuredRuntimeContextLimit"]),
            system_template_tokens=int(split["systemTemplateTokens"]),
            input_budget_tokens=int(split["inputBudgetTokens"]),
            output_reserve_tokens=int(split["outputReserveTokens"]),
            safety_margin_tokens=int(split["safetyMarginTokens"]),
            characters_per_token=float(spec["charactersPerToken"]),
            requires_formatted_prompt_count=bool(spec["requiresFormattedPromptCount"]),
            enforce_max_output_tokens=bool(spec["enforceMaxOutputTokens"]),
        )
    return profiles


def context_profile_for_model(model_version_id: str) -> ContextProfileSpec | None:
    for profile in _load_context_profiles().values():
        if profile.model_version_id == model_version_id:
            return profile
    return None


def default_qwen_context_profile() -> ContextProfileSpec:
    profiles = _load_context_profiles()
    if not profiles:
        raise RuntimeError("no context profiles loaded")
    return next(iter(profiles.values()))
