from __future__ import annotations

import pytest
from edgemint.dev import task_type_catalog


def test_catalog_contains_core_task_types() -> None:
    entry = task_type_catalog.get_task_type("document.ocr")
    assert entry is not None
    assert entry.input_mode == "document"
    assert task_type_catalog.pipeline_family("ocr.receipt") == "document.ocr"
    assert task_type_catalog.pipeline_family("safety.nsfw_detection") == "image.classify"


def test_search_task_types() -> None:
    payload = task_type_catalog.list_catalog(query="رسید", locale="fa")
    assert payload["total"] >= 1
    assert any(item["value"] == "ocr.receipt" for item in payload["items"])


def test_enrich_task_row_adds_labels() -> None:
    enriched = task_type_catalog.enrich_task_row({"id": "tsk_x", "taskType": "ocr.invoice"})
    assert enriched["taskTypeLabel"] == "OCR invoice"
    assert enriched["taskTypeMeta"]["pipelineFamily"] == "document.ocr"
    assert enriched["taskTypeMeta"]["supported"] is True


def test_validate_unknown_task_type() -> None:
    with pytest.raises(ValueError, match="UNSUPPORTED_TASK_TYPE"):
        task_type_catalog.validate_task_submission(task_type="unknown.task")


def test_validate_allows_empty_input_for_dev_samples() -> None:
    entry = task_type_catalog.validate_task_submission(task_type="document.ocr")
    assert entry.value == "document.ocr"


def test_validate_image_task_requires_image_file() -> None:
    with pytest.raises(ValueError, match="INPUT_IMAGE_REQUIRED"):
        task_type_catalog.validate_task_submission(
            task_type="safety.nsfw_detection",
            file_bytes=b"not-an-image",
            file_mime="text/plain",
            file_name="notes.txt",
        )
