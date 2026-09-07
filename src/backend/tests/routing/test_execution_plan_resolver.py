from __future__ import annotations

from edgemint.routing.execution_plan_resolver import resolve_execution_plan


def test_long_text_summarize_uses_map_reduce_plan() -> None:
    plan = resolve_execution_plan(task_type="text.summarize", estimated_input_tokens=8000)
    assert plan.plan_name == "text-summarize-map-reduce"
    operations = [stage.operation for stage in plan.stages]
    assert operations == ["chunk", "llm_map", "llm_reduce", "validate", "submit"]


def test_short_text_summarize_uses_direct_plan() -> None:
    plan = resolve_execution_plan(task_type="text.summarize", estimated_input_tokens=500)
    assert plan.plan_name == "text-summarize-direct"
    assert len(plan.stages) == 2


def test_document_summarize_matches_architecture_stages() -> None:
    plan = resolve_execution_plan(task_type="document.summarize", page_count=3)
    assert plan.plan_name == "document-summarize"
    assert len(plan.stages) == 8
    assert plan.stages[4].operation == "llm_map"
    assert plan.stages[5].operation == "llm_reduce"
