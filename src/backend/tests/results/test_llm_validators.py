from __future__ import annotations

import json

from edgemint.golden.harness import run_golden_task
from edgemint.results.validator import validate_task_result

LLM_TASK_TYPES = (
    "llm.summary_verification",
    "llm.hallucination_check",
    "llm.ocr_output_validation",
    "llm.policy_violation",
    "llm.prompt_output_consistency",
    "llm.answer_quality_score",
    "llm.suspicious_output",
)


def _envelope(task_type: str, data: dict[str, object]) -> str:
    return json.dumps(
        {
            "schemaVersion": "1",
            "taskId": f"tsk_{task_type.replace('.', '_')}",
            "status": "SUCCEEDED",
            "output": {"data": data},
            "metrics": {"llmMs": 400},
        }
    )


def test_llm_summary_verification_golden_passes() -> None:
    assert run_golden_task("llm.summary_verification").passed is True


def test_llm_hallucination_check_requires_claims_when_hallucinated() -> None:
    outcome = validate_task_result(
        task_type="llm.hallucination_check",
        inline_output=_envelope(
            "llm.hallucination_check",
            {"hallucinated": True, "riskScore": 0.8, "unsupportedClaims": []},
        ),
    )
    assert outcome.valid is False


def test_llm_policy_violation_golden_passes() -> None:
    assert run_golden_task("llm.policy_violation").passed is True


def test_llm_suspicious_output_requires_signals_when_suspicious() -> None:
    outcome = validate_task_result(
        task_type="llm.suspicious_output",
        inline_output=_envelope(
            "llm.suspicious_output",
            {"suspicious": True, "riskScore": 0.9, "signals": []},
        ),
    )
    assert outcome.valid is False


def test_all_llm_golden_fixtures_pass() -> None:
    for task_type in LLM_TASK_TYPES:
        outcome = run_golden_task(task_type)
        assert outcome.passed is True, task_type
