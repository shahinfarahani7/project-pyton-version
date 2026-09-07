from __future__ import annotations

from edgemint.golden.harness import run_golden_task
from edgemint.results.vision_validators import VISION_VALIDATORS
from edgemint.tasks.catalog_closure import inspect_catalog_entry, validate_queue_admission
from edgemint.dev.task_type_catalog import get_task_type

VISION_TASK_TYPES = tuple(sorted(VISION_VALIDATORS.keys()))


def test_all_vision_golden_fixtures_pass() -> None:
    for task_type in VISION_TASK_TYPES:
        outcome = run_golden_task(task_type)
        assert outcome.passed is True, task_type


def test_vision_task_admitted_to_queue_after_closure() -> None:
    entry = validate_queue_admission(catalog_code="image.classify", mode="strict")
    assert entry.executable is True
    report = inspect_catalog_entry(entry)
    assert report.dsl_contract_complete is True
    assert report.golden_fixture_present is True
    assert report.queue_admissible is True


def test_vision_contract_complete_for_all_fourteen() -> None:
    for task_type in VISION_TASK_TYPES:
        entry = get_task_type(task_type)
        assert entry is not None
        report = inspect_catalog_entry(entry)
        assert report.contract_complete is True, task_type
