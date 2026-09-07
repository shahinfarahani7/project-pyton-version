from __future__ import annotations

from pathlib import Path

from edgemint.dev.task_type_catalog import get_task_type, supported_task_types
from edgemint.routing.checkpoint_policy_matrix import CheckpointPolicyMatrix, catalog_task_types
from edgemint.routing.execution_plan_resolver import resolve_execution_plan


def test_matrix_covers_all_catalog_task_types() -> None:
    matrix = CheckpointPolicyMatrix.load()
    catalog = set(catalog_task_types())
    assert len(catalog) == 56
    assert set(matrix.entries.keys()) == catalog


def test_long_running_tasks_enable_checkpoint() -> None:
    matrix = CheckpointPolicyMatrix.load()
    for task_type in ("text.summarize", "document.ocr", "document.extract"):
        policy = matrix.entry(task_type)
        assert policy is not None
        assert policy.checkpoint_enabled is True
        assert policy.checkpoint_strategy in {"chunk", "stage"}


def test_short_tasks_disable_checkpoint() -> None:
    matrix = CheckpointPolicyMatrix.load()
    for task_type in ("text.classify", "image.classify", "safety.nsfw_detection"):
        policy = matrix.entry(task_type)
        assert policy is not None
        assert policy.checkpoint_enabled is False
        assert policy.checkpoint_strategy == "none"


def test_catalog_json_has_explicit_checkpoint_flags() -> None:
    enabled = 0
    disabled = 0
    for task_type in supported_task_types():
        entry = get_task_type(task_type)
        assert entry is not None
        assert entry.checkpoint_policy_ref == "CheckpointPolicyMatrix/task-checkpoint-matrix-v1@1.0.0"
        assert entry.checkpoint_strategy in {"none", "chunk", "stage"}
        if entry.checkpoint_enabled:
            enabled += 1
            assert entry.checkpoint_strategy != "none"
        else:
            disabled += 1
            assert entry.checkpoint_strategy == "none"
    assert enabled == 15
    assert disabled == 41


def test_execution_plan_resolver_uses_matrix_for_short_task() -> None:
    plan = resolve_execution_plan(task_type="text.classify")
    assert plan.stages[0].checkpoint_enabled is False


def test_execution_plan_resolver_uses_matrix_for_ocr_task() -> None:
    plan = resolve_execution_plan(task_type="document.ocr")
    assert plan.stages[0].checkpoint_enabled is True


def test_export_snapshot_matches_matrix() -> None:
    root = Path(__file__).resolve().parents[4]
    matrix = CheckpointPolicyMatrix.load(root=root)
    export = {
        row.task_type: {
            "checkpointEnabled": row.checkpoint_enabled,
            "checkpointStrategy": row.checkpoint_strategy,
        }
        for row in sorted(matrix.entries.values(), key=lambda item: item.task_type)
    }
    assert len(export) == 56
    assert export["text.summarize"]["checkpointEnabled"] is True
    assert export["text.classify"]["checkpointEnabled"] is False
