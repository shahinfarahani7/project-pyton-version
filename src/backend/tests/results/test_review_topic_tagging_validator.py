from __future__ import annotations

import json

from edgemint.results.validator import validate_task_result


def _worker_topic_tagging_envelope(
    *,
    tags: list[str] | None = None,
    confidence: float = 0.9,
) -> str:
    tag_list = tags if tags is not None else ["battery_life"]
    return json.dumps(
        {
            "schemaVersion": "1",
            "taskId": "tsk_topic_tagging",
            "status": "SUCCEEDED",
            "output": {
                "data": {
                    "tags": tag_list,
                    "confidence": confidence,
                }
            },
            "metrics": {"llmMs": 320},
        }
    )


def test_review_topic_tagging_valid_passes() -> None:
    outcome = validate_task_result(
        task_type="review.topic_tagging",
        inline_output=_worker_topic_tagging_envelope(),
    )
    assert outcome.valid is True


def test_review_topic_tagging_empty_tags_rejected() -> None:
    outcome = validate_task_result(
        task_type="review.topic_tagging",
        inline_output=_worker_topic_tagging_envelope(tags=[]),
    )
    assert outcome.valid is False
    assert outcome.failure_code == "RESULT_VALIDATION_FAILED"


def test_review_topic_tagging_invalid_confidence_rejected() -> None:
    outcome = validate_task_result(
        task_type="review.topic_tagging",
        inline_output=_worker_topic_tagging_envelope(confidence=1.5),
    )
    assert outcome.valid is False
    assert outcome.failure_code in {"RESULT_SCHEMA_INVALID", "RESULT_VALIDATION_FAILED"}
