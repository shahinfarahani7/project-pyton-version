from __future__ import annotations

import json

from edgemint.results.validator import validate_task_result


def _worker_sentiment_envelope(
    *,
    sentiment: str = "positive",
    confidence: float = 0.87,
    aspects: list[str] | None = None,
) -> str:
    aspect_list = aspects if aspects is not None else ["quality:positive"]
    return json.dumps(
        {
            "schemaVersion": "1",
            "taskId": "tsk_sentiment",
            "status": "SUCCEEDED",
            "output": {
                "data": {
                    "sentiment": sentiment,
                    "confidence": confidence,
                    "aspects": aspect_list,
                }
            },
            "metrics": {"llmMs": 350},
        }
    )


def test_review_sentiment_valid_passes() -> None:
    outcome = validate_task_result(
        task_type="review.sentiment",
        inline_output=_worker_sentiment_envelope(),
    )
    assert outcome.valid is True


def test_review_sentiment_empty_sentiment_rejected() -> None:
    outcome = validate_task_result(
        task_type="review.sentiment",
        inline_output=_worker_sentiment_envelope(sentiment="  "),
    )
    assert outcome.valid is False
    assert outcome.failure_code == "RESULT_VALIDATION_FAILED"


def test_review_sentiment_empty_aspects_rejected() -> None:
    outcome = validate_task_result(
        task_type="review.sentiment",
        inline_output=_worker_sentiment_envelope(aspects=[]),
    )
    assert outcome.valid is False
    assert outcome.failure_code == "RESULT_VALIDATION_FAILED"
