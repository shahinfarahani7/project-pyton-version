from __future__ import annotations

import json

from edgemint.results.validator import validate_task_result


def _worker_fake_detection_envelope(
    *,
    fake: bool = True,
    risk_score: float = 0.9,
    signals: list[str] | None = None,
) -> str:
    signal_list = signals if signals is not None else (["repetitive_praise"] if fake else [])
    return json.dumps(
        {
            "schemaVersion": "1",
            "taskId": "tsk_fake_detection",
            "status": "SUCCEEDED",
            "output": {
                "data": {
                    "fake": fake,
                    "riskScore": risk_score,
                    "signals": signal_list,
                }
            },
            "metrics": {"llmMs": 400},
        }
    )


def test_review_fake_detection_valid_passes() -> None:
    outcome = validate_task_result(
        task_type="review.fake_detection",
        inline_output=_worker_fake_detection_envelope(),
    )
    assert outcome.valid is True


def test_review_fake_detection_requires_signals_when_fake() -> None:
    outcome = validate_task_result(
        task_type="review.fake_detection",
        inline_output=_worker_fake_detection_envelope(fake=True, signals=[]),
    )
    assert outcome.valid is False
    assert outcome.failure_code == "RESULT_VALIDATION_FAILED"


def test_review_fake_detection_genuine_review_passes() -> None:
    outcome = validate_task_result(
        task_type="review.fake_detection",
        inline_output=_worker_fake_detection_envelope(fake=False, risk_score=0.1, signals=[]),
    )
    assert outcome.valid is True
