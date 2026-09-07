from __future__ import annotations

from edgemint.golden.harness import run_golden_task
from edgemint.results.gap_validators import GAP_VALIDATORS
from edgemint.tasks.catalog_closure import inspect_catalog_entry, validate_catalog_sync, validate_queue_admission
from edgemint.dev.task_type_catalog import get_task_type, supported_task_types

GAP_TASK_TYPES = tuple(sorted(GAP_VALIDATORS.keys()))


def test_all_gap_golden_fixtures_pass() -> None:
    for task_type in GAP_TASK_TYPES:
        outcome = run_golden_task(task_type)
        assert outcome.passed is True, task_type


def test_ocr_family_admitted_to_queue_after_closure() -> None:
    entry = validate_queue_admission(catalog_code="ocr.receipt", mode="strict")
    assert entry.executable is True
    report = inspect_catalog_entry(entry)
    assert report.contract_complete is True


def test_gap_contract_complete_for_all_seven() -> None:
    for task_type in GAP_TASK_TYPES:
        entry = get_task_type(task_type)
        assert entry is not None
        report = inspect_catalog_entry(entry)
        assert report.contract_complete is True, task_type


def test_all_fifty_six_executable_tasks_have_golden_and_dsl() -> None:
    reports = validate_catalog_sync()
    assert len(reports) == 56
    incomplete = [
        report.task_type
        for report in reports
        if report.executable and not report.contract_complete
    ]
    assert incomplete == []
    assert len(supported_task_types()) == 56
