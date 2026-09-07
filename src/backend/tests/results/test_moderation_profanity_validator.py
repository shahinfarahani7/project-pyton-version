from __future__ import annotations

import json

from edgemint.results.validator import validate_task_result


def _worker_profanity_envelope(
    *,
    contains_profanity: bool = False,
    confidence: float = 0.95,
    spans: list[str] | None = None,
) -> str:
    span_list = spans if spans is not None else (["badword"] if contains_profanity else [])
    return json.dumps(
        {
            "schemaVersion": "1",
            "taskId": "tsk_profanity",
            "status": "SUCCEEDED",
            "output": {
                "data": {
                    "containsProfanity": contains_profanity,
                    "confidence": confidence,
                    "spans": span_list,
                }
            },
            "metrics": {"llmMs": 300},
        }
    )


def test_moderation_profanity_clean_text_passes() -> None:
    outcome = validate_task_result(
        task_type="moderation.profanity",
        inline_output=_worker_profanity_envelope(),
    )
    assert outcome.valid is True


def test_moderation_profanity_detected_requires_spans() -> None:
    outcome = validate_task_result(
        task_type="moderation.profanity",
        inline_output=_worker_profanity_envelope(contains_profanity=True, spans=[]),
    )
    assert outcome.valid is False
    assert outcome.failure_code == "RESULT_VALIDATION_FAILED"


def test_moderation_profanity_detected_with_spans_passes() -> None:
    outcome = validate_task_result(
        task_type="moderation.profanity",
        inline_output=_worker_profanity_envelope(contains_profanity=True, spans=["badword"]),
    )
    assert outcome.valid is True
