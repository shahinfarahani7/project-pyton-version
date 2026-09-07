from __future__ import annotations

import json

import pytest

from edgemint.golden.harness import (
    GoldenFixture,
    load_fixture,
    run_golden_fixture,
    run_golden_task,
    tamper_worker_result,
)


def test_document_ocr_golden_fixture_passes() -> None:
    outcome = run_golden_task("document.ocr")
    assert outcome.passed is True
    assert outcome.validation_valid is True
    assert outcome.golden_status == "passed"
    assert len(outcome.result_sha256) == 64


def test_text_summarize_golden_fixture_passes() -> None:
    outcome = run_golden_task("text.summarize")
    assert outcome.passed is True
    assert outcome.validation_valid is True
    assert outcome.golden_status == "passed"
    assert len(outcome.result_sha256) == 64


def test_text_classify_golden_fixture_passes() -> None:
    outcome = run_golden_task("text.classify")
    assert outcome.passed is True
    assert outcome.validation_valid is True
    assert outcome.golden_status == "passed"


def test_moderation_prompt_safety_golden_fixture_passes() -> None:
    outcome = run_golden_task("moderation.prompt_safety")
    assert outcome.passed is True
    assert outcome.validation_valid is True
    assert outcome.golden_status == "passed"


def test_moderation_text_golden_fixture_passes() -> None:
    outcome = run_golden_task("moderation.text")
    assert outcome.passed is True
    assert outcome.validation_valid is True
    assert outcome.golden_status == "passed"


def test_moderation_profanity_golden_fixture_passes() -> None:
    outcome = run_golden_task("moderation.profanity")
    assert outcome.passed is True
    assert outcome.validation_valid is True
    assert outcome.golden_status == "passed"


def test_moderation_spam_comment_golden_fixture_passes() -> None:
    outcome = run_golden_task("moderation.spam_comment")
    assert outcome.passed is True
    assert outcome.validation_valid is True
    assert outcome.golden_status == "passed"


def test_review_fake_detection_golden_fixture_passes() -> None:
    outcome = run_golden_task("review.fake_detection")
    assert outcome.passed is True
    assert outcome.validation_valid is True
    assert outcome.golden_status == "passed"


def test_review_sentiment_golden_fixture_passes() -> None:
    outcome = run_golden_task("review.sentiment")
    assert outcome.passed is True
    assert outcome.validation_valid is True
    assert outcome.golden_status == "passed"


def test_review_topic_tagging_golden_fixture_passes() -> None:
    outcome = run_golden_task("review.topic_tagging")
    assert outcome.passed is True
    assert outcome.validation_valid is True
    assert outcome.golden_status == "passed"


@pytest.mark.parametrize(
    "task_type",
    [
        "llm.summary_verification",
        "llm.hallucination_check",
        "llm.ocr_output_validation",
        "llm.policy_violation",
        "llm.prompt_output_consistency",
        "llm.answer_quality_score",
        "llm.suspicious_output",
        "nlp.language_detection",
        "nlp.text_classification",
        "nlp.spam_fraud_classification",
        "ml.bot_abuse_risk",
        "document.extract",
        "extract.amount",
        "extract.date",
        "extract.order_number",
        "extract.document_type",
        "catalog.fake_listing",
        "llm.ai_tag_validation",
        "llm.caption_validation",
        "dataset.label_verification",
        "dataset.duplicate_cleanup",
        "dataset.low_quality_removal",
        "ml.active_learning_prelabel",
        "ml.consensus_label_validation",
        "ml.human_verification_quality",
    ],
)
def test_llm_golden_fixtures_pass(task_type: str) -> None:
    outcome = run_golden_task(task_type)
    assert outcome.passed is True
    assert outcome.validation_valid is True
    assert outcome.golden_status == "passed"


def test_fixture_loader_validates_schema() -> None:
    fixture = load_fixture("document.ocr")
    assert fixture.task_type == "document.ocr"
    assert fixture.input_payload["assetRef"] == "file_golden_ocr_001"
    assert "rawText" in fixture.worker_result["output"]


def test_tampered_output_fails_validation() -> None:
    fixture = load_fixture("document.ocr")
    tampered = GoldenFixture(
        task_type=fixture.task_type,
        fixture_version=fixture.fixture_version,
        input_payload=fixture.input_payload,
        worker_result=tamper_worker_result(fixture.worker_result),
        minimum_confidence_milli=fixture.minimum_confidence_milli,
    )
    outcome = run_golden_fixture(tampered)
    assert outcome.passed is False
    assert outcome.validation_valid is False


def test_expected_sha256_mismatch_fails() -> None:
    fixture = load_fixture("document.ocr")
    mismatched = GoldenFixture(
        task_type=fixture.task_type,
        fixture_version=fixture.fixture_version,
        input_payload=fixture.input_payload,
        worker_result=fixture.worker_result,
        expected_result_sha256="0" * 64,
        minimum_confidence_milli=fixture.minimum_confidence_milli,
    )
    outcome = run_golden_fixture(mismatched)
    assert outcome.passed is False
    assert outcome.failure_reason == "result_sha256_mismatch"


def test_fixture_document_matches_schema_file() -> None:
    fixture = load_fixture("document.ocr")
    payload = json.loads(fixture.path.read_text(encoding="utf-8"))  # type: ignore[union-attr]
    assert payload["taskType"] == fixture.task_type
    assert payload["workerResult"]["status"] == "SUCCEEDED"
