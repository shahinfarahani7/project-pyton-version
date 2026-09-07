from __future__ import annotations

import json

from edgemint.results.validator import (
    ResultValidationContext,
    ResultValidatorRegistry,
    extract_task_result_payload,
    validate_task_result,
)


def _worker_ocr_envelope(*, raw_text: str = "hello", confidence: float = 0.92) -> str:
    return json.dumps(
        {
            "schemaVersion": "1",
            "taskId": "tsk_ocr",
            "status": "SUCCEEDED",
            "output": {
                "rawText": raw_text,
                "ocrLines": [{"text": raw_text, "confidence": confidence, "box": [0, 0, 1, 1]}],
            },
            "metrics": {"averageOcrConfidence": confidence, "ocrMs": 120},
        }
    )


def test_document_ocr_valid_worker_envelope_passes() -> None:
    outcome = validate_task_result(task_type="document.ocr", inline_output=_worker_ocr_envelope())
    assert outcome.valid is True
    assert outcome.schema_valid is True
    assert outcome.business_rules_valid is True


def test_document_ocr_empty_text_rejected() -> None:
    payload = json.dumps(
        {
            "schemaVersion": "1",
            "taskId": "tsk_ocr",
            "status": "SUCCEEDED",
            "output": {"rawText": "   ", "ocrLines": []},
            "metrics": {"averageOcrConfidence": 0.9},
        }
    )
    outcome = validate_task_result(task_type="document.ocr", inline_output=payload)
    assert outcome.valid is False
    assert outcome.failure_code == "RESULT_VALIDATION_FAILED"


def test_document_ocr_invalid_json_rejected() -> None:
    outcome = validate_task_result(task_type="document.ocr", inline_output="{not-json")
    assert outcome.valid is False
    assert outcome.failure_code == "RESULT_SCHEMA_INVALID"


def test_document_ocr_task_native_shape_passes() -> None:
    payload = json.dumps(
        {
            "status": "succeeded",
            "data": {"rawText": "page one", "ocrLines": []},
            "metrics": {"averageOcrConfidence": 0.88},
        }
    )
    outcome = validate_task_result(task_type="document.ocr", inline_output=payload)
    assert outcome.valid is True


def test_registry_allows_custom_validator() -> None:
    registry = ResultValidatorRegistry()

    def reject_all(context: ResultValidationContext, payload: dict[str, object]) -> object:
        from edgemint.results.validator import ResultValidationOutcome

        return ResultValidationOutcome(
            valid=False,
            schema_valid=True,
            business_rules_valid=False,
            failure_code="RESULT_VALIDATION_FAILED",
            detail="blocked",
        )

    registry.register("custom.task", reject_all)  # type: ignore[arg-type]
    outcome = registry.validate(
        ResultValidationContext(
            task_type="custom.task",
            inline_output=json.dumps({"status": "succeeded", "data": {"x": 1}, "metrics": {}}),
        )
    )
    assert outcome.valid is False


def test_extract_task_result_payload_maps_worker_envelope() -> None:
    envelope = json.loads(_worker_ocr_envelope())
    payload = extract_task_result_payload(envelope)
    assert payload["status"] == "succeeded"
    assert payload["data"]["rawText"] == "hello"
