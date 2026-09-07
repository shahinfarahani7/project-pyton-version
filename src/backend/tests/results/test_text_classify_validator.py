from __future__ import annotations

import json

from edgemint.results.validator import validate_task_result


def _worker_classify_envelope(
    *,
    label: str = "security",
    confidence: float = 0.91,
    evidence: list[str] | None = None,
) -> str:
    items = evidence if evidence is not None else ["verification code"]
    return json.dumps(
        {
            "schemaVersion": "1",
            "taskId": "tsk_classify",
            "status": "SUCCEEDED",
            "output": {
                "data": {
                    "label": label,
                    "confidence": confidence,
                    "evidence": items,
                }
            },
            "metrics": {"llmMs": 500},
        }
    )


def test_text_classify_valid_worker_envelope_passes() -> None:
    outcome = validate_task_result(task_type="text.classify", inline_output=_worker_classify_envelope())
    assert outcome.valid is True


def test_text_classify_empty_label_rejected() -> None:
    outcome = validate_task_result(
        task_type="text.classify",
        inline_output=_worker_classify_envelope(label="  "),
    )
    assert outcome.valid is False
    assert outcome.failure_code == "RESULT_VALIDATION_FAILED"


def test_text_classify_invalid_confidence_rejected() -> None:
    outcome = validate_task_result(
        task_type="text.classify",
        inline_output=_worker_classify_envelope(confidence=1.5),
    )
    assert outcome.valid is False
    assert outcome.failure_code in {"RESULT_SCHEMA_INVALID", "RESULT_VALIDATION_FAILED"}


def test_text_classify_empty_evidence_rejected() -> None:
    outcome = validate_task_result(
        task_type="text.classify",
        inline_output=_worker_classify_envelope(evidence=[]),
    )
    assert outcome.valid is False
    assert outcome.failure_code == "RESULT_VALIDATION_FAILED"
