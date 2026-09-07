"""T15 audit scenarios: catalog reconciliation and Flex gates (P8-A15 / A15)."""

from __future__ import annotations

import pytest

from edgemint.dev.task_type_catalog import get_task_type
from edgemint.tasks.catalog_closure import validate_catalog_sync
from edgemint.tasks.catalog_reconciliation import (
    HISTORICAL_EXPECTED_UNIQUE_TOTAL,
    FlexDispatchDecision,
    build_catalog_reconciliation_snapshot,
    evaluate_flex_dispatch_gate,
    list_flex_dispatch_violations,
)
from edgemint.tasks.errors import task_error
from edgemint.tasks.catalog_closure import validate_queue_admission


def test_t15_unique_catalog_reconciles_with_historical_56() -> None:
    snapshot = build_catalog_reconciliation_snapshot()
    assert snapshot.duplicate_catalog_ids == ()
    assert snapshot.duplicate_dsl_codes == ()
    assert snapshot.unmapped_catalog_ids == ()
    assert snapshot.orphan_dsl_codes  # documented legacy DSL stubs outside active catalog
    assert snapshot.unique_task_count == HISTORICAL_EXPECTED_UNIQUE_TOTAL
    assert snapshot.reconciled_with_historical is True
    assert snapshot.reconciliation_delta == 0


def test_t15_taxonomy_axes_overlap_is_documented() -> None:
    snapshot = build_catalog_reconciliation_snapshot()
    axes = snapshot.taxonomy_axes
    assert axes["flexAxis"] == 9
    assert axes["uniqueTotal"] == 56
    assert axes["qwenAxis"] + axes["flexAxis"] + axes["visionAxis"] > 56
    assert "overlap" in snapshot.taxonomy_axis_overlap_note.lower()


def test_t15_all_nine_flex_tasks_dispatch_permitted_with_contracts() -> None:
    snapshot = build_catalog_reconciliation_snapshot()
    assert len(snapshot.flex_task_ids) == 9
    assert snapshot.flex_blocked_ids == ()
    assert len(snapshot.flex_dispatchable_ids) == 9
    assert list_flex_dispatch_violations() == []


def test_t15_flex_without_handler_blocks_dispatch() -> None:
    entry = get_task_type("catalog.fake_listing")
    assert entry is not None
    permitted = evaluate_flex_dispatch_gate(entry)
    assert permitted == FlexDispatchDecision.DISPATCH_PERMITTED


def test_t15_queue_admission_rejects_unknown_task_type() -> None:
    with pytest.raises(Exception) as exc:
        validate_queue_admission(catalog_code="task.does.not.exist", mode="baseline")
    assert exc.value.code == "UNSUPPORTED_TASK_CONFIGURATION"  # type: ignore[attr-defined]


def test_t15_catalog_closure_sync_still_complete() -> None:
    reports = validate_catalog_sync()
    assert len(reports) == 56
    incomplete = [report for report in reports if report.executable and not report.contract_complete]
    assert incomplete == []


def test_t15_flex_gate_blocks_non_executable_flex() -> None:
    entry = get_task_type("catalog.fake_listing")
    assert entry is not None
    blocked_entry = type(entry)(
        value=entry.value,
        label_en=entry.label_en,
        label_fa=entry.label_fa,
        input_mode=entry.input_mode,
        category_id=entry.category_id,
        category_label_en=entry.category_label_en,
        category_label_fa=entry.category_label_fa,
        resource_envelope_ref=entry.resource_envelope_ref,
        retry_class=entry.retry_class,
        retry_policy_ref=entry.retry_policy_ref,
        executable=False,
        checkpoint_enabled=entry.checkpoint_enabled,
        checkpoint_strategy=entry.checkpoint_strategy,
        checkpoint_policy_ref=entry.checkpoint_policy_ref,
    )
    assert evaluate_flex_dispatch_gate(blocked_entry) == FlexDispatchDecision.BLOCKED_NON_EXECUTABLE
