from __future__ import annotations

from edgemint.golden.harness import run_golden_task

NLP_ML_TASK_TYPES = (
    "nlp.language_detection",
    "nlp.text_classification",
    "nlp.spam_fraud_classification",
    "ml.bot_abuse_risk",
)


def test_all_nlp_ml_golden_fixtures_pass() -> None:
    for task_type in NLP_ML_TASK_TYPES:
        outcome = run_golden_task(task_type)
        assert outcome.passed is True, task_type
