from __future__ import annotations

import pytest
from edgemint.tasks.errors import TaskServiceError
from edgemint.tasks.lifecycle import (
    TaskLifecycle,
    map_db_execution_status,
    map_db_lifecycle_to_api,
    priority_mapping,
)
from edgemint.tasks.validation import load_task_type_contracts, validate_task_submission


def test_lifecycle_matches_dsl_transitions() -> None:
    lifecycle = TaskLifecycle.load()
    assert lifecycle.can_transition("draft", "submitted")
    assert lifecycle.can_transition("submitted", "cancelled")
    assert not lifecycle.can_transition("cancelled", "submitted")


def test_lifecycle_rejects_invalid_cancel() -> None:
    lifecycle = TaskLifecycle.load()
    with pytest.raises(TaskServiceError) as exc:
        lifecycle.assert_transition("completed", "cancelled")
    assert exc.value.code == "TASK_NOT_CANCELLABLE"


def test_priority_mapping() -> None:
    assert priority_mapping("batch") == ("batch", 1000)
    assert priority_mapping("realtime") == ("critical", 4000)


def test_api_status_projection() -> None:
    assert map_db_lifecycle_to_api("queued") == "submitted"
    assert map_db_execution_status("queued") == "queued"


def test_validate_document_ocr_submission() -> None:
    contract = validate_task_submission(
        api_task_type="document-ocr",
        content_type="application/pdf",
        contracts=load_task_type_contracts(),
    )
    assert contract.code == "document.ocr"


def test_rejects_unknown_task_type() -> None:
    with pytest.raises(TaskServiceError) as exc:
        validate_task_submission(
            api_task_type="unknown-task",
            content_type="application/pdf",
            contracts=load_task_type_contracts(),
        )
    assert exc.value.code == "UNSUPPORTED_TASK_CONFIGURATION"
