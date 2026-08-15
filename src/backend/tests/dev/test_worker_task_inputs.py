from __future__ import annotations

from edgemint.dev import worker_task_inputs


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
