"""T18 audit scenarios: contract-specific semantic quality validation (P8-A18 / A18)."""

from __future__ import annotations

import json

from edgemint.results.semantic_quality import evaluate_semantic_quality
from edgemint.results.validator import extract_task_result_payload, validate_task_result
from edgemint.routing.quality_escalation import (
    escalation_class_for_failure,
    escalated_verification_tier,
)


def _extract_amount_payload(*, amount: float, evidence: str, confidence: float = 0.5) -> dict:
    return {
        "status": "succeeded",
        "data": {"amount": amount, "currency": "EUR", "evidence": evidence},
        "metrics": {"confidence": confidence},
    }


def test_t18_valid_json_wrong_amount_content_fails_semantic_quality() -> None:
    payload = _extract_amount_payload(amount=999.9, evidence="Amount due: EUR 49.90")
    outcome = validate_task_result(
        task_type="extract.amount",
        inline_output=json.dumps({"output": payload}),
        task_input={"expectedAmount": 49.9},
    )
    assert outcome.schema_valid is True
    assert outcome.business_rules_valid is True
    assert outcome.semantic_quality_valid is False
    assert outcome.valid is False
    assert outcome.failure_code == "SEMANTIC_QUALITY_FAILED"


def test_t18_correct_amount_passes_semantic_quality() -> None:
    payload = _extract_amount_payload(amount=49.9, evidence="Amount due: EUR 49.90")
    outcome = validate_task_result(
        task_type="extract.amount",
        inline_output=json.dumps({"output": payload}),
        task_input={"expectedAmount": 49.9},
    )
    assert outcome.valid is True
    assert outcome.semantic_quality_valid is True


def test_t18_self_reported_high_confidence_does_not_bypass_wrong_content() -> None:
    payload = _extract_amount_payload(
        amount=12.0,
        evidence="Amount due: EUR 49.90",
        confidence=0.99,
    )
    semantic = evaluate_semantic_quality(
        task_type="extract.amount",
        payload=payload,
        task_input={"expectedAmount": 49.9},
    )
    assert semantic.valid is False
    assert semantic.self_reported_confidence_ignored is True
    outcome = validate_task_result(
        task_type="extract.amount",
        inline_output=json.dumps({"output": payload}),
        task_input={"expectedAmount": 49.9},
    )
    assert "self-reported confidence is not sufficient proof" in (outcome.detail or "")


def test_t18_wrong_geometry_and_label_vocabulary_rejected() -> None:
    payload = {
        "status": "succeeded",
        "data": {
            "label": "unknown_class",
            "confidence": 0.95,
            "evidence": ["shape"],
            "bbox": [0.2, 0.2, 0.0, 0.5],
        },
        "metrics": {},
    }
    outcome = validate_task_result(
        task_type="image.classify",
        inline_output=json.dumps({"output": payload}),
        task_input={"allowedLabels": ["cat", "dog"], "expectedLabel": "cat"},
    )
    assert outcome.schema_valid is True
    assert outcome.valid is False
    assert outcome.failure_code == "SEMANTIC_QUALITY_FAILED"


def test_t18_quality_escalation_distinct_from_capacity() -> None:
    assert escalation_class_for_failure("SEMANTIC_QUALITY_FAILED") == "quality"
    assert escalation_class_for_failure("MODEL_UNAVAILABLE") == "capacity"
    assert escalated_verification_tier(current_tier="standard", failure_code="SEMANTIC_QUALITY_FAILED") == "high"
    assert escalated_verification_tier(current_tier="standard", failure_code="MODEL_UNAVAILABLE") == "standard"


def test_t18_document_extract_wrong_total_rejected() -> None:
    payload = {
        "status": "succeeded",
        "data": {"vendor": "Acme", "total": 100.0, "currency": "USD"},
        "metrics": {},
    }
    outcome = validate_task_result(
        task_type="document.extract",
        inline_output=json.dumps({"output": payload}),
        task_input={"expectedTotal": 49.9},
    )
    assert outcome.valid is False
    assert outcome.semantic_quality_valid is False
    extracted = extract_task_result_payload({"output": payload})
    assert extracted["data"]["total"] == 100.0
