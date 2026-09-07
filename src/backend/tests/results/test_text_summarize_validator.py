from __future__ import annotations

import json

from edgemint.results.validator import (
    extract_task_result_payload,
    validate_task_result,
)


def _worker_summarize_envelope(
    *,
    summary: str = "Workers summarize assigned text with Qwen.",
    key_points: list[str] | None = None,
) -> str:
    points = key_points if key_points is not None else ["Qwen map/reduce path", "Fence-token assignments"]
    return json.dumps(
        {
            "schemaVersion": "1",
            "taskId": "tsk_summarize",
            "status": "SUCCEEDED",
            "output": {
                "data": {
                    "summary": summary,
                    "keyPoints": points,
                    "missingOrUnclear": [],
                }
            },
            "metrics": {"llmMs": 900, "inputTokens": 20, "outputTokens": 30},
        }
    )


def test_text_summarize_valid_worker_envelope_passes() -> None:
    outcome = validate_task_result(task_type="text.summarize", inline_output=_worker_summarize_envelope())
    assert outcome.valid is True
    assert outcome.schema_valid is True
    assert outcome.business_rules_valid is True


def test_text_summarize_empty_summary_rejected() -> None:
    payload = _worker_summarize_envelope(summary="   ")
    outcome = validate_task_result(task_type="text.summarize", inline_output=payload)
    assert outcome.valid is False
    assert outcome.failure_code == "RESULT_VALIDATION_FAILED"


def test_text_summarize_empty_key_points_rejected() -> None:
    payload = _worker_summarize_envelope(key_points=[])
    outcome = validate_task_result(task_type="text.summarize", inline_output=payload)
    assert outcome.valid is False
    assert outcome.failure_code == "RESULT_VALIDATION_FAILED"


def test_extract_task_result_payload_unwraps_nested_data() -> None:
    envelope = json.loads(_worker_summarize_envelope())
    payload = extract_task_result_payload(envelope)
    assert payload["status"] == "succeeded"
    assert payload["data"]["summary"].startswith("Workers summarize")
    assert len(payload["data"]["keyPoints"]) == 2


def test_text_summarize_task_native_shape_passes() -> None:
    payload = json.dumps(
        {
            "status": "succeeded",
            "data": {
                "summary": "Short summary.",
                "keyPoints": ["One point"],
                "missingOrUnclear": ["none"],
            },
            "metrics": {"llmMs": 100},
        }
    )
    outcome = validate_task_result(task_type="text.summarize", inline_output=payload)
    assert outcome.valid is True
