from __future__ import annotations

import json

from edgemint.results.validator import validate_task_result


def _worker_moderation_text_envelope(
    *,
    allowed: bool = True,
    risk_score: float = 0.1,
    categories: list[str] | None = None,
    reason: str = "Benign customer feedback.",
) -> str:
    cats = categories if categories is not None else ["benign_feedback"]
    return json.dumps(
        {
            "schemaVersion": "1",
            "taskId": "tsk_moderation_text",
            "status": "SUCCEEDED",
            "output": {
                "data": {
                    "allowed": allowed,
                    "riskScore": risk_score,
                    "categories": cats,
                    "reason": reason,
                }
            },
            "metrics": {"llmMs": 350},
        }
    )


def test_moderation_text_valid_worker_envelope_passes() -> None:
    outcome = validate_task_result(
        task_type="moderation.text",
        inline_output=_worker_moderation_text_envelope(),
    )
    assert outcome.valid is True


def test_moderation_text_empty_reason_rejected() -> None:
    outcome = validate_task_result(
        task_type="moderation.text",
        inline_output=_worker_moderation_text_envelope(reason="  "),
    )
    assert outcome.valid is False
    assert outcome.failure_code == "RESULT_VALIDATION_FAILED"


def test_moderation_text_empty_categories_rejected() -> None:
    outcome = validate_task_result(
        task_type="moderation.text",
        inline_output=_worker_moderation_text_envelope(categories=[]),
    )
    assert outcome.valid is False
    assert outcome.failure_code == "RESULT_VALIDATION_FAILED"
