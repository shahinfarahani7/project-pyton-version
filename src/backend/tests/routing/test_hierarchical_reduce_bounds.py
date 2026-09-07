from __future__ import annotations

from edgemint.routing.hierarchical_reduce_policy import (
    classify_reduce_exhaustion,
    default_text_summarize_reduce_bounds,
    estimate_token_mass,
    made_reduce_progress,
)


def test_default_bounds_loaded_from_execution_plan_dsl() -> None:
    bounds = default_text_summarize_reduce_bounds()
    assert bounds.max_chunks == 64
    assert bounds.max_reduce_depth == 8
    assert bounds.max_inference_calls == 128
    assert bounds.progress_rule.value == "groups_or_token_mass_must_decrease"


def test_made_reduce_progress_by_group_reduction() -> None:
    bounds = default_text_summarize_reduce_bounds()
    assert made_reduce_progress(
        before_groups=4,
        after_groups=2,
        before_token_mass=1000,
        after_token_mass=1000,
        min_token_mass_reduction_ratio_milli=bounds.min_token_mass_reduction_ratio_milli,
    )


def test_nonshrinking_reduce_detected() -> None:
    bounds = default_text_summarize_reduce_bounds()
    assert not made_reduce_progress(
        before_groups=3,
        after_groups=3,
        before_token_mass=400,
        after_token_mass=400,
        min_token_mass_reduction_ratio_milli=bounds.min_token_mass_reduction_ratio_milli,
    )


def test_classify_reduce_depth_exhaustion() -> None:
    bounds = default_text_summarize_reduce_bounds()
    reason = classify_reduce_exhaustion(
        depth=bounds.max_reduce_depth,
        inference_calls=1,
        bounds=bounds,
        chunk_count=10,
    )
    assert reason == "max_reduce_depth_exceeded"


def test_classify_chunk_cap_exceeded() -> None:
    bounds = default_text_summarize_reduce_bounds()
    reason = classify_reduce_exhaustion(
        depth=0,
        inference_calls=0,
        bounds=bounds,
        chunk_count=bounds.max_chunks + 1,
    )
    assert reason == "chunk_cap_exceeded"


def test_token_mass_estimator_is_stable() -> None:
    first = estimate_token_mass([{"summary": "alpha", "keyPoints": ["a"]}])
    second = estimate_token_mass([{"keyPoints": ["a"], "summary": "alpha"}])
    assert first == second
