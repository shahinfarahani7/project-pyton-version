"""Task-specific semantic quality validation (Architecture v2 §48, A18/T18)."""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True, slots=True)
class SemanticQualityOutcome:
    valid: bool
    failure_code: str | None = None
    detail: str | None = None
    self_reported_confidence_ignored: bool = False


def _status_failed(payload: dict[str, Any]) -> bool:
    return str(payload.get("status", "")).lower() == "failed"


def _parse_amount_from_evidence(evidence: str) -> float | None:
    match = re.search(r"(\d+(?:\.\d+)?)", evidence.replace(",", ""))
    if not match:
        return None
    return float(match.group(1))


def _extract_amount_semantic(
    payload: dict[str, Any],
    task_input: dict[str, Any] | None,
) -> SemanticQualityOutcome:
    if _status_failed(payload):
        return SemanticQualityOutcome(valid=True)
    data = payload.get("data")
    if not isinstance(data, dict):
        return SemanticQualityOutcome(valid=False, failure_code="SEMANTIC_QUALITY_FAILED", detail="missing data")
    amount = data.get("amount")
    evidence = data.get("evidence")
    if not isinstance(amount, (int, float)):
        return SemanticQualityOutcome(valid=False, failure_code="SEMANTIC_QUALITY_FAILED", detail="missing amount")
    if not isinstance(evidence, str) or evidence.strip() == "":
        return SemanticQualityOutcome(valid=False, failure_code="SEMANTIC_QUALITY_FAILED", detail="missing evidence")

    parsed = _parse_amount_from_evidence(evidence)
    if parsed is None or abs(float(amount) - parsed) > 0.01:
        return SemanticQualityOutcome(
            valid=False,
            failure_code="SEMANTIC_QUALITY_FAILED",
            detail="amount does not match evidence text",
            self_reported_confidence_ignored=_high_self_reported_confidence(payload),
        )

    if task_input:
        expected = task_input.get("expectedAmount")
        if expected is not None and abs(float(amount) - float(expected)) > 0.01:
            return SemanticQualityOutcome(
                valid=False,
                failure_code="SEMANTIC_QUALITY_FAILED",
                detail="amount does not match task input ground truth",
                self_reported_confidence_ignored=_high_self_reported_confidence(payload),
            )
    return SemanticQualityOutcome(valid=True)


def _document_extract_semantic(
    payload: dict[str, Any],
    task_input: dict[str, Any] | None,
) -> SemanticQualityOutcome:
    if _status_failed(payload):
        return SemanticQualityOutcome(valid=True)
    data = payload.get("data")
    if not isinstance(data, dict):
        return SemanticQualityOutcome(valid=False, failure_code="SEMANTIC_QUALITY_FAILED", detail="missing data")
    total = data.get("total")
    if not isinstance(total, (int, float)):
        return SemanticQualityOutcome(valid=False, failure_code="SEMANTIC_QUALITY_FAILED", detail="missing total")
    if task_input:
        expected_total = task_input.get("expectedTotal")
        if expected_total is not None and abs(float(total) - float(expected_total)) > 0.01:
            return SemanticQualityOutcome(
                valid=False,
                failure_code="SEMANTIC_QUALITY_FAILED",
                detail="total does not match task input ground truth",
                self_reported_confidence_ignored=_high_self_reported_confidence(payload),
            )
    return SemanticQualityOutcome(valid=True)


def _image_classify_semantic(
    payload: dict[str, Any],
    task_input: dict[str, Any] | None,
) -> SemanticQualityOutcome:
    if _status_failed(payload):
        return SemanticQualityOutcome(valid=True)
    data = payload.get("data")
    if not isinstance(data, dict):
        return SemanticQualityOutcome(valid=False, failure_code="SEMANTIC_QUALITY_FAILED", detail="missing data")
    label = data.get("label")
    if not isinstance(label, str) or label.strip() == "":
        return SemanticQualityOutcome(valid=False, failure_code="SEMANTIC_QUALITY_FAILED", detail="missing label")

    if task_input:
        allowed = task_input.get("allowedLabels")
        if isinstance(allowed, list) and allowed and label not in allowed:
            return SemanticQualityOutcome(
                valid=False,
                failure_code="SEMANTIC_QUALITY_FAILED",
                detail="label not in allowed vocabulary",
                self_reported_confidence_ignored=_high_self_reported_confidence(payload),
            )
        expected_label = task_input.get("expectedLabel")
        if expected_label is not None and label != expected_label:
            return SemanticQualityOutcome(
                valid=False,
                failure_code="SEMANTIC_QUALITY_FAILED",
                detail="label does not match expected ground truth",
                self_reported_confidence_ignored=_high_self_reported_confidence(payload),
            )

    bbox = data.get("bbox")
    if bbox is not None:
        if not isinstance(bbox, list) or len(bbox) != 4:
            return SemanticQualityOutcome(
                valid=False,
                failure_code="SEMANTIC_QUALITY_FAILED",
                detail="bbox must be [x, y, width, height]",
            )
        x, y, width, height = (float(value) for value in bbox)
        if min(x, y, width, height) < 0 or max(x + width, y + height) > 1.0001:
            return SemanticQualityOutcome(
                valid=False,
                failure_code="SEMANTIC_QUALITY_FAILED",
                detail="bbox geometry out of normalized bounds",
            )
        if width <= 0 or height <= 0:
            return SemanticQualityOutcome(
                valid=False,
                failure_code="SEMANTIC_QUALITY_FAILED",
                detail="bbox width and height must be positive",
            )
    return SemanticQualityOutcome(valid=True)


def _high_self_reported_confidence(payload: dict[str, Any]) -> bool:
    metrics = payload.get("metrics")
    if not isinstance(metrics, dict):
        return False
    for key in ("confidence", "averageOcrConfidence", "qualityScore"):
        value = metrics.get(key)
        if isinstance(value, (int, float)) and float(value) >= 0.9:
            return True
    data = payload.get("data")
    if isinstance(data, dict):
        confidence = data.get("confidence")
        if isinstance(confidence, (int, float)) and float(confidence) >= 0.9:
            return True
    return False


_SEMANTIC_EVALUATORS: dict[str, Any] = {
    "extract.amount": _extract_amount_semantic,
    "document.extract": _document_extract_semantic,
    "image.classify": _image_classify_semantic,
}


def evaluate_semantic_quality(
    *,
    task_type: str,
    payload: dict[str, Any],
    task_input: dict[str, Any] | None = None,
) -> SemanticQualityOutcome:
    """Apply task-specific truth/quality criteria after schema/business validation."""
    evaluator = _SEMANTIC_EVALUATORS.get(task_type)
    if evaluator is None:
        return SemanticQualityOutcome(valid=True)
    return evaluator(payload, task_input)
