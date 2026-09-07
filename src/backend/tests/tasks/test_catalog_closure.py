from __future__ import annotations

from edgemint.tasks.catalog_closure import (
    inspect_catalog_entry,
    validate_catalog_sync,
    validate_queue_admission,
)
from edgemint.dev.task_type_catalog import get_task_type


def test_catalog_sync_has_56_entries_with_complete_metadata() -> None:
    reports = validate_catalog_sync()
    assert len(reports) == 56
    incomplete = [report for report in reports if report.executable and not report.metadata_complete]
    assert incomplete == []


def test_executable_task_passes_baseline_gate() -> None:
    entry = validate_queue_admission(catalog_code="document.ocr", mode="baseline")
    assert entry.value == "document.ocr"


def test_flex_task_admitted_after_closure() -> None:
    entry = validate_queue_admission(catalog_code="catalog.fake_listing", mode="baseline")
    assert entry.executable is True


def test_strict_mode_requires_dsl_contract_for_unclosed_task() -> None:
    """After full catalog closure all executable tasks pass strict mode."""
    entry = validate_queue_admission(catalog_code="catalog.duplicate_image", mode="strict")
    assert entry.value == "catalog.duplicate_image"


def test_document_ocr_has_canonical_gap_classification() -> None:
    entry = get_task_type("document.ocr")
    assert entry is not None
    report = inspect_catalog_entry(entry)
    assert report.contract_complete is True


def test_warn_only_skips_closure_gate() -> None:
    entry = validate_queue_admission(catalog_code="catalog.product_classification", mode="warn_only")
    assert entry.value == "catalog.product_classification"


def test_document_ocr_has_dsl_contract_in_catalog_report() -> None:
    entry = get_task_type("document.ocr")
    assert entry is not None
    report = inspect_catalog_entry(entry)
    assert report.metadata_complete is True
    assert report.dsl_contract_complete is True
    assert report.golden_fixture_present is True
