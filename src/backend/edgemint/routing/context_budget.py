from __future__ import annotations

import math
from dataclasses import dataclass
from enum import StrEnum

from edgemint.routing.context_profile_registry import ContextProfileSpec, default_qwen_context_profile


class ContextExecutionRoute(StrEnum):
    DIRECT_INFERENCE = "direct_inference"
    CHUNK_PIPELINE = "chunk_pipeline"


class OutputTerminationReason(StrEnum):
    COMPLETE = "complete"
    TRUNCATED_BY_LIMIT = "truncated_by_limit"
    INVALID_OUTPUT = "invalid_output"


@dataclass(frozen=True, slots=True)
class FormattedPromptEvaluation:
    formatted_prompt_tokens: int
    effective_context_limit: int
    max_output_tokens: int
    safety_tokens: int
    total_required_tokens: int
    route: ContextExecutionRoute
    fits_direct_inference: bool


@dataclass(frozen=True, slots=True)
class OutputLimitEvaluation:
    estimated_output_tokens: int
    max_output_tokens: int
    reason: OutputTerminationReason
    treat_as_success: bool


def estimate_tokens(text: str, *, characters_per_token: float = 3.5) -> int:
    if not text:
        return 0
    return max(1, math.ceil(len(text) / characters_per_token))


def effective_context_limit(
    *,
    verified_artifact_context_limit: int,
    configured_runtime_context_limit: int,
    task_policy_context_limit: int,
) -> int:
    return min(
        verified_artifact_context_limit,
        configured_runtime_context_limit,
        task_policy_context_limit,
    )


def evaluate_formatted_prompt(
    *,
    formatted_prompt: str,
    max_output_tokens: int,
    profile: ContextProfileSpec | None = None,
    task_policy_context_limit: int | None = None,
) -> FormattedPromptEvaluation:
    spec = profile or default_qwen_context_profile()
    prompt_tokens = estimate_tokens(
        formatted_prompt,
        characters_per_token=spec.characters_per_token,
    )
    safety_tokens = spec.safety_margin_tokens
    effective_limit = effective_context_limit(
        verified_artifact_context_limit=spec.verified_artifact_context_limit,
        configured_runtime_context_limit=spec.configured_runtime_context_limit,
        task_policy_context_limit=task_policy_context_limit or spec.verified_artifact_context_limit,
    )
    capped_output = min(max_output_tokens, spec.output_reserve_tokens)
    total_required = prompt_tokens + capped_output + safety_tokens
    exceeds_input = prompt_tokens > spec.input_budget_tokens
    exceeds_total = total_required > effective_limit
    route = (
        ContextExecutionRoute.CHUNK_PIPELINE
        if exceeds_input or exceeds_total
        else ContextExecutionRoute.DIRECT_INFERENCE
    )
    return FormattedPromptEvaluation(
        formatted_prompt_tokens=prompt_tokens,
        effective_context_limit=effective_limit,
        max_output_tokens=capped_output,
        safety_tokens=safety_tokens,
        total_required_tokens=total_required,
        route=route,
        fits_direct_inference=route == ContextExecutionRoute.DIRECT_INFERENCE,
    )


def cap_max_output_tokens(
    requested: int,
    *,
    profile: ContextProfileSpec | None = None,
) -> int:
    spec = profile or default_qwen_context_profile()
    return max(1, min(requested, spec.output_reserve_tokens))


def evaluate_output_limit(
    *,
    raw_output: str,
    max_output_tokens: int,
    profile: ContextProfileSpec | None = None,
    json_required: bool = True,
) -> OutputLimitEvaluation:
    spec = profile or default_qwen_context_profile()
    capped = cap_max_output_tokens(max_output_tokens, profile=spec)
    estimated = estimate_tokens(raw_output, characters_per_token=spec.characters_per_token)
    if estimated > capped:
        return OutputLimitEvaluation(
            estimated_output_tokens=estimated,
            max_output_tokens=capped,
            reason=OutputTerminationReason.TRUNCATED_BY_LIMIT,
            treat_as_success=False,
        )
    if json_required and raw_output.strip() and not raw_output.strip().startswith("{"):
        return OutputLimitEvaluation(
            estimated_output_tokens=estimated,
            max_output_tokens=capped,
            reason=OutputTerminationReason.INVALID_OUTPUT,
            treat_as_success=False,
        )
    return OutputLimitEvaluation(
        estimated_output_tokens=estimated,
        max_output_tokens=capped,
        reason=OutputTerminationReason.COMPLETE,
        treat_as_success=True,
    )
