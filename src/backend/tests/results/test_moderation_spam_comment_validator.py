from __future__ import annotations

import json

from edgemint.results.validator import validate_task_result


def _worker_spam_comment_envelope(
    *,
    spam: bool = False,
    confidence: float = 0.9,
    signals: list[str] | None = None,
) -> str:
    signal_list = signals if signals is not None else (["promotional_cta"] if spam else [])
    return json.dumps(
        {
            "schemaVersion": "1",
            "taskId": "tsk_spam_comment",
            "status": "SUCCEEDED",
            "output": {
                "data": {
                    "spam": spam,
                    "confidence": confidence,
                    "signals": signal_list,
                }
            },
            "metrics": {"llmMs": 320},
        }
    )


def test_moderation_spam_comment_benign_passes() -> None:
    outcome = validate_task_result(
        task_type="moderation.spam_comment",
        inline_output=_worker_spam_comment_envelope(),
    )
    assert outcome.valid is True


def test_moderation_spam_comment_spam_requires_signals() -> None:
    outcome = validate_task_result(
        task_type="moderation.spam_comment",
        inline_output=_worker_spam_comment_envelope(spam=True, signals=[]),
    )
    assert outcome.valid is False
    assert outcome.failure_code == "RESULT_VALIDATION_FAILED"


def test_moderation_spam_comment_spam_with_signals_passes() -> None:
    outcome = validate_task_result(
        task_type="moderation.spam_comment",
        inline_output=_worker_spam_comment_envelope(spam=True, signals=["repeated_link"]),
    )
    assert outcome.valid is True
