from __future__ import annotations

import json

from edgemint.results.validator import validate_task_result


def _worker_prompt_safety_envelope(
    *,
    safe: bool = True,
    risk_score: float = 0.12,
    categories: list[str] | None = None,
    reason: str = "Benign security guidance request.",
) -> str:
    cats = categories if categories is not None else ["account_security"]
    return json.dumps(
        {
            "schemaVersion": "1",
            "taskId": "tsk_prompt_safety",
            "status": "SUCCEEDED",
            "output": {
                "data": {
                    "safe": safe,
                    "riskScore": risk_score,
                    "categories": cats,
                    "reason": reason,
                }
            },
            "metrics": {"llmMs": 400},
        }
    )


def test_moderation_prompt_safety_valid_worker_envelope_passes() -> None:
    outcome = validate_task_result(
        task_type="moderation.prompt_safety",
        inline_output=_worker_prompt_safety_envelope(),
    )
    assert outcome.valid is True


def test_moderation_prompt_safety_empty_reason_rejected() -> None:
    outcome = validate_task_result(
        task_type="moderation.prompt_safety",
        inline_output=_worker_prompt_safety_envelope(reason="  "),
    )
    assert outcome.valid is False
    assert outcome.failure_code == "RESULT_VALIDATION_FAILED"


def test_moderation_prompt_safety_empty_categories_rejected() -> None:
    outcome = validate_task_result(
        task_type="moderation.prompt_safety",
        inline_output=_worker_prompt_safety_envelope(categories=[]),
    )
    assert outcome.valid is False
    assert outcome.failure_code == "RESULT_VALIDATION_FAILED"


def test_moderation_prompt_safety_invalid_risk_score_rejected() -> None:
    outcome = validate_task_result(
        task_type="moderation.prompt_safety",
        inline_output=_worker_prompt_safety_envelope(risk_score=1.2),
    )
    assert outcome.valid is False
    assert outcome.failure_code in {"RESULT_SCHEMA_INVALID", "RESULT_VALIDATION_FAILED"}
