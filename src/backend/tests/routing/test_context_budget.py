from __future__ import annotations

import json

from edgemint.routing.context_budget import (
    ContextExecutionRoute,
    OutputTerminationReason,
    cap_max_output_tokens,
    effective_context_limit,
    evaluate_formatted_prompt,
    evaluate_output_limit,
)
from edgemint.routing.context_profile_registry import default_qwen_context_profile


def test_effective_context_limit_uses_minimum_of_three_sources() -> None:
    assert (
        effective_context_limit(
            verified_artifact_context_limit=1280,
            configured_runtime_context_limit=1200,
            task_policy_context_limit=1500,
        )
        == 1200
    )


def test_formatted_prompt_boundary_english_json() -> None:
    profile = default_qwen_context_profile()
    prompt = (
        "Return JSON only.\n---\n"
        + json.dumps({"label": "invoice", "confidence": 0.91})
        + "\n---\n/no_think"
    )
    evaluation = evaluate_formatted_prompt(
        formatted_prompt=prompt,
        max_output_tokens=300,
        profile=profile,
    )
    assert evaluation.route == ContextExecutionRoute.DIRECT_INFERENCE
    assert evaluation.formatted_prompt_tokens < profile.input_budget_tokens


def test_formatted_prompt_boundary_persian_mixed_routes_to_chunk() -> None:
    profile = default_qwen_context_profile()
    persian = "این یک متن فارسی است. " * 400
    mixed = f"{persian}\nEnglish summary required.\n---\n/no_think"
    evaluation = evaluate_formatted_prompt(
        formatted_prompt=mixed,
        max_output_tokens=300,
        profile=profile,
    )
    assert evaluation.route == ContextExecutionRoute.CHUNK_PIPELINE


def test_formatted_prompt_long_system_instruction_consumes_budget() -> None:
    profile = default_qwen_context_profile()
    long_system = "SYSTEM RULE: " * 200
    body = "short input\n---\n/no_think"
    evaluation = evaluate_formatted_prompt(
        formatted_prompt=f"{long_system}\n{body}",
        max_output_tokens=300,
        profile=profile,
    )
    assert evaluation.formatted_prompt_tokens > profile.input_budget_tokens
    assert evaluation.route == ContextExecutionRoute.CHUNK_PIPELINE


def test_output_limit_truncation_is_not_success() -> None:
    profile = default_qwen_context_profile()
    huge = '{"summary":"' + ("x" * 2000) + '"}'
    result = evaluate_output_limit(
        raw_output=huge,
        max_output_tokens=50,
        profile=profile,
        json_required=True,
    )
    assert result.reason == OutputTerminationReason.TRUNCATED_BY_LIMIT
    assert result.treat_as_success is False


def test_cap_max_output_tokens_respects_artifact_reserve() -> None:
    profile = default_qwen_context_profile()
    assert cap_max_output_tokens(512, profile=profile) == profile.output_reserve_tokens
