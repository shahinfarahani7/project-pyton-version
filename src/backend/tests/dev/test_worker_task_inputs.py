from __future__ import annotations

from edgemint.dev import worker_task_inputs
from edgemint.results.text_summarize_constraints import (
    DEFAULT_TEXT_SUMMARIZE_PORTAL_OPTIONS,
)
import pytest


def test_sample_document_ocr_manifest_includes_image_blob() -> None:
    worker_task_inputs.register_task(task_id="tsk_ocr_sample", task_type="document.ocr")
    manifest = worker_task_inputs.input_manifest("tsk_ocr_sample")
    assert manifest is not None
    assert manifest["inputContentUrl"]
    assert manifest["options"]["ocrOnly"] is True
    assert worker_task_inputs.input_content("tsk_ocr_sample") is not None


def test_pdf_upload_gets_input_content_url() -> None:
    worker_task_inputs.register_task(
        task_id="tsk_pdf_ocr",
        task_type="document.ocr",
        file_name="MFA.pdf",
        file_mime="application/pdf",
        file_bytes=b"%PDF-1.4 minimal test content for ocr pipeline",
    )
    manifest = worker_task_inputs.input_manifest("tsk_pdf_ocr")
    assert manifest is not None
    assert manifest["inputContentUrl"]
    blob = worker_task_inputs.input_content("tsk_pdf_ocr")
    assert blob is not None
    assert blob["bytes"][:4] == b"%PDF"


def test_text_classify_manifest_has_input_text() -> None:
    worker_task_inputs.register_task(task_id="tsk_txt_cls", task_type="text.classify")
    manifest = worker_task_inputs.input_manifest("tsk_txt_cls")
    assert manifest is not None
    assert manifest["inputText"]
    assert "allowedLabels" in manifest["options"]


def test_ensure_registered_builds_sample_manifest_when_missing() -> None:
    worker_task_inputs.ensure_registered(task_id="tsk_dev_missing", task_type="document.ocr")
    manifest = worker_task_inputs.input_manifest("tsk_dev_missing")
    assert manifest is not None
    assert manifest["taskType"] == "document.ocr"
    assert manifest["inputContentUrl"]


@pytest.mark.parametrize("task_type", [
    "catalog.fake_listing", "llm.ai_tag_validation", "llm.caption_validation",
    "dataset.label_verification", "dataset.duplicate_cleanup",
    "dataset.low_quality_removal", "ml.active_learning_prelabel",
    "ml.consensus_label_validation", "ml.human_verification_quality",
])
def test_flex_contract_has_structured_sample_and_output_schema(task_type: str) -> None:
    task_id = "tsk_" + task_type.replace(".", "_")
    worker_task_inputs.register_task(task_id=task_id, task_type=task_type)
    manifest = worker_task_inputs.input_manifest(task_id)
    assert manifest is not None
    assert isinstance(manifest["inputData"], dict) and manifest["inputData"]
    assert isinstance(manifest["options"]["outputSchema"], dict)


def test_flex_custom_payload_requires_json_object() -> None:
    with pytest.raises(ValueError, match="FLEX_INPUT_MUST_BE_JSON_OBJECT"):
        worker_task_inputs.register_task(
            task_id="tsk_bad_flex", task_type="dataset.label_verification",
            input_text="not-json",
        )


def test_generic_text_summarize_manifest_has_no_summarize_options() -> None:
    worker_task_inputs.register_task(
        task_id="tsk_generic_summarize",
        task_type="text.summarize",
        input_text="Generic customer feedback.",
        instructions="Summarize in your own words.",
    )
    manifest = worker_task_inputs.input_manifest("tsk_generic_summarize")
    assert manifest is not None
    assert "summarize" not in manifest["options"]


def test_explicit_grocery_summarize_options_persist_in_manifest() -> None:
    worker_task_inputs.register_task(
        task_id="tsk_grocery_summarize",
        task_type="text.summarize",
        input_text="Grocery feedback.",
        summarize_options=DEFAULT_TEXT_SUMMARIZE_PORTAL_OPTIONS,
    )
    manifest = worker_task_inputs.input_manifest("tsk_grocery_summarize")
    assert manifest is not None
    summarize = manifest["options"]["summarize"]
    assert summarize["keyPointCount"] == 5
    assert summarize["maxSummaryWords"] == 80
    assert "delivery" in summarize["coverageAxes"]


def test_custom_summarize_options_are_preserved() -> None:
    custom = {"schemaVersion": "1", "keyPointCount": 3, "maxSummaryWords": 120}
    worker_task_inputs.register_task(
        task_id="tsk_custom_summarize",
        task_type="text.summarize",
        input_text="Short feedback.",
        summarize_options=custom,
    )
    manifest = worker_task_inputs.input_manifest("tsk_custom_summarize")
    assert manifest is not None
    assert manifest["options"]["summarize"] == custom


def test_record_output_stores_full_result_text() -> None:
    from edgemint.dev import fixtures
    from edgemint.dev.fixtures import DEV_WORKSPACE_PRIMARY

    task = fixtures.create_dev_task(
        DEV_WORKSPACE_PRIMARY,
        task_type="text.summarize",
        input_text="Source body.",
    )
    long_result = "x" * 5000
    worker_task_inputs.record_output(task_id=task["id"], result_text=long_result)
    stored = fixtures.dev_task(DEV_WORKSPACE_PRIMARY, task["id"])
    assert stored is not None
    assert len(stored["resultText"]) == 5000
    assert len(stored["resultPreview"]) == fixtures._PREVIEW_RESULT_CHARS
