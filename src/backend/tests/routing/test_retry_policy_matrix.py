from __future__ import annotations

from pathlib import Path

from edgemint.dev.task_type_catalog import get_task_type, supported_task_types
from edgemint.routing.retry_classifier import RetryClass
from edgemint.routing.retry_policy_matrix import RetryPolicyMatrix, catalog_task_types
from edgemint.routing.service import RouterService


def test_matrix_covers_all_catalog_task_types() -> None:
    matrix = RetryPolicyMatrix.load()
    catalog = set(catalog_task_types())
    assert len(catalog) == 56
    assert set(matrix.entries.keys()) == catalog


def test_flex_tasks_are_non_executable_with_no_retry() -> None:
    matrix = RetryPolicyMatrix.load()
    flex_types = [
        task_type
        for task_type in supported_task_types()
        if (entry := get_task_type(task_type)) is not None and entry.input_mode == "flex"
    ]
    assert len(flex_types) == 9
    for task_type in flex_types:
        policy = matrix.entry(task_type)
        assert policy is not None
        assert policy.executable is False
        assert policy.retry_class == RetryClass.NO_RETRY


def test_text_summarize_prefers_stronger_worker() -> None:
    matrix = RetryPolicyMatrix.load()
    policy = matrix.entry("text.summarize")
    assert policy is not None
    assert policy.retry_class == RetryClass.STRONGER_WORKER
    assert matrix.resolve_retry_class(task_type="text.summarize", failure_code="RESOURCE_PRESSURE") == (
        RetryClass.STRONGER_WORKER
    )


def test_document_ocr_quality_failure_routes_stronger() -> None:
    matrix = RetryPolicyMatrix.load()
    resolved = matrix.resolve_retry_class(task_type="document.ocr", failure_code="OCR_EMPTY_RESULT")
    assert resolved == RetryClass.STRONGER_WORKER


def test_flex_task_retry_blocked_even_for_retryable_failure() -> None:
    matrix = RetryPolicyMatrix.load()
    resolved = matrix.resolve_retry_class(task_type="catalog.fake_listing", failure_code="RESOURCE_PRESSURE")
    assert resolved == RetryClass.NO_RETRY


def test_catalog_json_has_retry_class_on_every_type() -> None:
    for task_type in supported_task_types():
        entry = get_task_type(task_type)
        assert entry is not None
        assert entry.retry_class in {
            RetryClass.IMMEDIATE_OTHER_WORKER.value,
            RetryClass.STRONGER_WORKER.value,
            RetryClass.NO_RETRY.value,
        }
        assert entry.retry_policy_ref == "RetryPolicyMatrix/task-retry-matrix-v1@1.0.0"
        if entry.input_mode == "flex":
            assert entry.executable is False
        else:
            assert entry.executable is True


def test_router_service_uses_task_retry_matrix() -> None:
    router = RouterService()
    payload = router.classify_retry("RESOURCE_PRESSURE", task_type="text.summarize")
    assert payload["retryClass"] == RetryClass.STRONGER_WORKER.value
    blocked = router.classify_retry("RESOURCE_PRESSURE", task_type="dataset.label_verification")
    assert blocked["retryPermitted"] is False


def test_export_snapshot_matches_matrix() -> None:
    root = Path(__file__).resolve().parents[4]
    matrix = RetryPolicyMatrix.load(root=root)
    export = {
        row.task_type: {
            "retryClass": row.retry_class.value,
            "executable": row.executable,
        }
        for row in sorted(matrix.entries.values(), key=lambda item: item.task_type)
    }
    assert len(export) == 56
    assert export["catalog.fake_listing"]["executable"] is False
