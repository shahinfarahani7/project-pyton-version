from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Callable

from jsonschema import Draft202012Validator
from jsonschema.exceptions import ValidationError

from edgemint.results.semantic_quality import evaluate_semantic_quality
from edgemint.results.task_type_schemas import output_schema_for


@dataclass(frozen=True, slots=True)
class ResultValidationContext:
    task_type: str
    inline_output: str | None
    task_input: dict[str, Any] | None = None


@dataclass(frozen=True, slots=True)
class ResultValidationOutcome:
    valid: bool
    schema_valid: bool
    business_rules_valid: bool
    semantic_quality_valid: bool = True
    failure_code: str | None = None
    detail: str | None = None


ValidatorFn = Callable[[ResultValidationContext, dict[str, Any]], ResultValidationOutcome]


def _normalize_worker_status(raw: object) -> str:
    value = str(raw or "succeeded").strip().lower()
    if value in {"succeeded", "success", "ok"}:
        return "succeeded"
    if value in {"partial", "partial_success"}:
        return "partial"
    if value in {"failed", "failure", "error"}:
        return "failed"
    return value


def extract_task_result_payload(envelope: dict[str, Any]) -> dict[str, Any]:
    """Map worker envelope or task-native payload to TaskType outputSchema shape."""
    if "status" in envelope and "data" in envelope:
        return envelope
    if "output" in envelope and isinstance(envelope["output"], dict):
        inner = envelope["output"]
        if "status" in inner and "data" in inner:
            return inner
        task_data: dict[str, Any] = inner
        nested = inner.get("data")
        if isinstance(nested, dict):
            if (
                set(inner.keys()) == {"data"}
                or "rawText" in inner
                or "ocrLines" in inner
                or ("data" in inner and "visionRuntimeClass" in inner)
            ):
                task_data = nested
        if "visionRuntimeClass" in task_data:
            task_data = {key: value for key, value in task_data.items() if key != "visionRuntimeClass"}
        return {
            "status": _normalize_worker_status(envelope.get("status")),
            "data": task_data,
            "metrics": envelope.get("metrics", {}) if isinstance(envelope.get("metrics"), dict) else {},
        }
    return {
        "status": _normalize_worker_status(envelope.get("status", "succeeded")),
        "data": envelope,
        "metrics": envelope.get("metrics", {}) if isinstance(envelope.get("metrics"), dict) else {},
    }


def _validate_json_schema(payload: dict[str, Any], schema: dict[str, Any]) -> tuple[bool, str | None]:
    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(payload), key=lambda item: item.path)
    if not errors:
        return True, None
    first = errors[0]
    path = ".".join(str(part) for part in first.path)
    detail = f"{path}: {first.message}" if path else first.message
    return False, detail


def _document_ocr_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status == "failed":
        return True, None
    data = payload.get("data")
    if not isinstance(data, dict):
        return False, "ocr data must be an object"
    raw_text = data.get("rawText")
    ocr_lines = data.get("ocrLines")
    has_text = isinstance(raw_text, str) and raw_text.strip() != ""
    has_lines = isinstance(ocr_lines, list) and len(ocr_lines) > 0
    if not has_text and not has_lines:
        return False, "ocr result requires non-empty rawText or ocrLines"
    metrics = payload.get("metrics")
    if isinstance(metrics, dict):
        confidence = metrics.get("averageOcrConfidence")
        if confidence is not None and float(confidence) <= 0:
            return False, "ocr confidence must be positive when present"
    return True, None


def _text_summarize_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status == "failed":
        return True, None
    data = payload.get("data")
    if not isinstance(data, dict):
        return False, "summarize data must be an object"
    summary = data.get("summary")
    key_points = data.get("keyPoints")
    if not isinstance(summary, str) or summary.strip() == "":
        return False, "summarize result requires non-empty summary"
    if not isinstance(key_points, list) or len(key_points) == 0:
        return False, "summarize result requires at least one keyPoint"
    return True, None


def _text_classify_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status == "failed":
        return True, None
    data = payload.get("data")
    if not isinstance(data, dict):
        return False, "classify data must be an object"
    label = data.get("label")
    confidence = data.get("confidence")
    evidence = data.get("evidence")
    if not isinstance(label, str) or label.strip() == "":
        return False, "classify result requires non-empty label"
    if not isinstance(confidence, (int, float)) or float(confidence) < 0 or float(confidence) > 1:
        return False, "classify confidence must be between 0 and 1"
    if not isinstance(evidence, list) or len(evidence) == 0:
        return False, "classify result requires at least one evidence item"
    return True, None


def _moderation_prompt_safety_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status == "failed":
        return True, None
    data = payload.get("data")
    if not isinstance(data, dict):
        return False, "prompt safety data must be an object"
    safe = data.get("safe")
    risk_score = data.get("riskScore")
    categories = data.get("categories")
    reason = data.get("reason")
    if not isinstance(safe, bool):
        return False, "prompt safety result requires boolean safe"
    if not isinstance(risk_score, (int, float)) or float(risk_score) < 0 or float(risk_score) > 1:
        return False, "prompt safety riskScore must be between 0 and 1"
    if not isinstance(categories, list) or len(categories) == 0:
        return False, "prompt safety result requires at least one category"
    if not isinstance(reason, str) or reason.strip() == "":
        return False, "prompt safety result requires non-empty reason"
    return True, None


def _moderation_text_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status == "failed":
        return True, None
    data = payload.get("data")
    if not isinstance(data, dict):
        return False, "text moderation data must be an object"
    allowed = data.get("allowed")
    risk_score = data.get("riskScore")
    categories = data.get("categories")
    reason = data.get("reason")
    if not isinstance(allowed, bool):
        return False, "text moderation result requires boolean allowed"
    if not isinstance(risk_score, (int, float)) or float(risk_score) < 0 or float(risk_score) > 1:
        return False, "text moderation riskScore must be between 0 and 1"
    if not isinstance(categories, list) or len(categories) == 0:
        return False, "text moderation result requires at least one category"
    if not isinstance(reason, str) or reason.strip() == "":
        return False, "text moderation result requires non-empty reason"
    return True, None


def _moderation_profanity_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status == "failed":
        return True, None
    data = payload.get("data")
    if not isinstance(data, dict):
        return False, "profanity data must be an object"
    contains = data.get("containsProfanity")
    confidence = data.get("confidence")
    spans = data.get("spans")
    if not isinstance(contains, bool):
        return False, "profanity result requires boolean containsProfanity"
    if not isinstance(confidence, (int, float)) or float(confidence) < 0 or float(confidence) > 1:
        return False, "profanity confidence must be between 0 and 1"
    if not isinstance(spans, list):
        return False, "profanity spans must be an array"
    if contains and len(spans) == 0:
        return False, "profanity spans required when containsProfanity is true"
    return True, None


def _moderation_spam_comment_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status == "failed":
        return True, None
    data = payload.get("data")
    if not isinstance(data, dict):
        return False, "spam comment data must be an object"
    spam = data.get("spam")
    confidence = data.get("confidence")
    signals = data.get("signals")
    if not isinstance(spam, bool):
        return False, "spam comment result requires boolean spam"
    if not isinstance(confidence, (int, float)) or float(confidence) < 0 or float(confidence) > 1:
        return False, "spam comment confidence must be between 0 and 1"
    if not isinstance(signals, list):
        return False, "spam comment signals must be an array"
    if spam and len(signals) == 0:
        return False, "spam signals required when spam is true"
    return True, None


def _review_fake_detection_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status == "failed":
        return True, None
    data = payload.get("data")
    if not isinstance(data, dict):
        return False, "fake detection data must be an object"
    fake = data.get("fake")
    risk_score = data.get("riskScore")
    signals = data.get("signals")
    if not isinstance(fake, bool):
        return False, "fake detection result requires boolean fake"
    if not isinstance(risk_score, (int, float)) or float(risk_score) < 0 or float(risk_score) > 1:
        return False, "fake detection riskScore must be between 0 and 1"
    if not isinstance(signals, list):
        return False, "fake detection signals must be an array"
    if fake and len(signals) == 0:
        return False, "fake detection signals required when fake is true"
    return True, None


def _review_sentiment_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status == "failed":
        return True, None
    data = payload.get("data")
    if not isinstance(data, dict):
        return False, "review sentiment data must be an object"
    sentiment = data.get("sentiment")
    confidence = data.get("confidence")
    aspects = data.get("aspects")
    if not isinstance(sentiment, str) or sentiment.strip() == "":
        return False, "review sentiment requires non-empty sentiment"
    if not isinstance(confidence, (int, float)) or float(confidence) < 0 or float(confidence) > 1:
        return False, "review sentiment confidence must be between 0 and 1"
    if not isinstance(aspects, list) or len(aspects) == 0:
        return False, "review sentiment requires at least one aspect"
    return True, None


def _review_topic_tagging_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status == "failed":
        return True, None
    data = payload.get("data")
    if not isinstance(data, dict):
        return False, "topic tagging data must be an object"
    tags = data.get("tags")
    confidence = data.get("confidence")
    if not isinstance(tags, list) or len(tags) == 0:
        return False, "topic tagging requires at least one tag"
    if not isinstance(confidence, (int, float)) or float(confidence) < 0 or float(confidence) > 1:
        return False, "topic tagging confidence must be between 0 and 1"
    return True, None


def _score_in_unit_interval(value: object, field_name: str) -> tuple[bool, str | None]:
    if not isinstance(value, (int, float)) or float(value) < 0 or float(value) > 1:
        return False, f"{field_name} must be between 0 and 1"
    return True, None


def _llm_summary_verification_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status == "failed":
        return True, None
    data = payload.get("data")
    if not isinstance(data, dict):
        return False, "summary verification data must be an object"
    if not isinstance(data.get("valid"), bool):
        return False, "summary verification requires boolean valid"
    ok, detail = _score_in_unit_interval(data.get("coverageScore"), "coverageScore")
    if not ok:
        return False, detail
    for field in ("unsupportedClaims", "missingPoints"):
        if not isinstance(data.get(field), list):
            return False, f"summary verification {field} must be an array"
    return True, None


def _llm_hallucination_check_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status == "failed":
        return True, None
    data = payload.get("data")
    if not isinstance(data, dict):
        return False, "hallucination check data must be an object"
    hallucinated = data.get("hallucinated")
    if not isinstance(hallucinated, bool):
        return False, "hallucination check requires boolean hallucinated"
    ok, detail = _score_in_unit_interval(data.get("riskScore"), "riskScore")
    if not ok:
        return False, detail
    claims = data.get("unsupportedClaims")
    if not isinstance(claims, list):
        return False, "hallucination unsupportedClaims must be an array"
    if hallucinated and len(claims) == 0:
        return False, "unsupportedClaims required when hallucinated is true"
    return True, None


def _llm_ocr_output_validation_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status == "failed":
        return True, None
    data = payload.get("data")
    if not isinstance(data, dict):
        return False, "ocr output validation data must be an object"
    if not isinstance(data.get("valid"), bool):
        return False, "ocr output validation requires boolean valid"
    ok, detail = _score_in_unit_interval(data.get("qualityScore"), "qualityScore")
    if not ok:
        return False, detail
    if not isinstance(data.get("issues"), list):
        return False, "ocr output validation issues must be an array"
    corrected = data.get("correctedText")
    if not isinstance(corrected, str):
        return False, "ocr output validation correctedText must be a string"
    return True, None


def _llm_policy_violation_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status == "failed":
        return True, None
    data = payload.get("data")
    if not isinstance(data, dict):
        return False, "policy violation data must be an object"
    if not isinstance(data.get("violates"), bool):
        return False, "policy violation requires boolean violates"
    severity = data.get("severity")
    if not isinstance(severity, str) or severity.strip() == "":
        return False, "policy violation requires non-empty severity"
    policies = data.get("policies")
    if not isinstance(policies, list) or len(policies) == 0:
        return False, "policy violation requires at least one policy"
    reason = data.get("reason")
    if not isinstance(reason, str) or reason.strip() == "":
        return False, "policy violation requires non-empty reason"
    return True, None


def _llm_prompt_output_consistency_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status == "failed":
        return True, None
    data = payload.get("data")
    if not isinstance(data, dict):
        return False, "prompt output consistency data must be an object"
    if not isinstance(data.get("consistent"), bool):
        return False, "prompt output consistency requires boolean consistent"
    ok, detail = _score_in_unit_interval(data.get("score"), "score")
    if not ok:
        return False, detail
    if not isinstance(data.get("issues"), list):
        return False, "prompt output consistency issues must be an array"
    return True, None


def _llm_answer_quality_score_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status == "failed":
        return True, None
    data = payload.get("data")
    if not isinstance(data, dict):
        return False, "answer quality score data must be an object"
    ok, detail = _score_in_unit_interval(data.get("score"), "score")
    if not ok:
        return False, detail
    dimensions = data.get("dimensions")
    if not isinstance(dimensions, dict) or len(dimensions) == 0:
        return False, "answer quality score requires non-empty dimensions"
    if not isinstance(data.get("issues"), list):
        return False, "answer quality score issues must be an array"
    return True, None


def _llm_suspicious_output_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status == "failed":
        return True, None
    data = payload.get("data")
    if not isinstance(data, dict):
        return False, "suspicious output data must be an object"
    suspicious = data.get("suspicious")
    if not isinstance(suspicious, bool):
        return False, "suspicious output requires boolean suspicious"
    ok, detail = _score_in_unit_interval(data.get("riskScore"), "riskScore")
    if not ok:
        return False, detail
    signals = data.get("signals")
    if not isinstance(signals, list):
        return False, "suspicious output signals must be an array"
    if suspicious and len(signals) == 0:
        return False, "suspicious output signals required when suspicious is true"
    return True, None


def _nlp_language_detection_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status == "failed":
        return True, None
    data = payload.get("data")
    if not isinstance(data, dict):
        return False, "language detection data must be an object"
    language = data.get("language")
    if not isinstance(language, str) or language.strip() == "":
        return False, "language detection requires non-empty language"
    ok, detail = _score_in_unit_interval(data.get("confidence"), "confidence")
    if not ok:
        return False, detail
    if not isinstance(data.get("alternatives"), list):
        return False, "language detection alternatives must be an array"
    return True, None


def _nlp_text_classification_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    return _text_classify_business_rules(_context, payload)


def _nlp_spam_fraud_classification_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status == "failed":
        return True, None
    data = payload.get("data")
    if not isinstance(data, dict):
        return False, "spam fraud classification data must be an object"
    label = data.get("label")
    if not isinstance(label, str) or label.strip() == "":
        return False, "spam fraud classification requires non-empty label"
    ok, detail = _score_in_unit_interval(data.get("confidence"), "confidence")
    if not ok:
        return False, detail
    signals = data.get("signals")
    if not isinstance(signals, list) or len(signals) == 0:
        return False, "spam fraud classification requires at least one signal"
    return True, None


def _ml_bot_abuse_risk_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status == "failed":
        return True, None
    data = payload.get("data")
    if not isinstance(data, dict):
        return False, "bot abuse risk data must be an object"
    risk = data.get("risk")
    if not isinstance(risk, str) or risk.strip() == "":
        return False, "bot abuse risk requires non-empty risk"
    ok, detail = _score_in_unit_interval(data.get("score"), "score")
    if not ok:
        return False, detail
    signals = data.get("signals")
    if not isinstance(signals, list) or len(signals) == 0:
        return False, "bot abuse risk requires at least one signal"
    return True, None


def _document_extract_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status == "failed":
        return True, None
    data = payload.get("data")
    if not isinstance(data, dict):
        return False, "document extract data must be an object"
    vendor = data.get("vendor")
    total = data.get("total")
    currency = data.get("currency")
    if not isinstance(vendor, str) or vendor.strip() == "":
        return False, "document extract requires non-empty vendor"
    if not isinstance(total, (int, float)) or float(total) <= 0:
        return False, "document extract total must be positive"
    if not isinstance(currency, str) or currency.strip() == "":
        return False, "document extract requires non-empty currency"
    return True, None


def _extract_amount_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status == "failed":
        return True, None
    data = payload.get("data")
    if not isinstance(data, dict):
        return False, "extract amount data must be an object"
    amount = data.get("amount")
    currency = data.get("currency")
    evidence = data.get("evidence")
    if not isinstance(amount, (int, float)) or float(amount) <= 0:
        return False, "extract amount must be positive"
    if not isinstance(currency, str) or currency.strip() == "":
        return False, "extract amount requires non-empty currency"
    if not isinstance(evidence, str) or evidence.strip() == "":
        return False, "extract amount requires non-empty evidence"
    return True, None


def _extract_date_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status == "failed":
        return True, None
    data = payload.get("data")
    if not isinstance(data, dict):
        return False, "extract date data must be an object"
    date_value = data.get("date")
    original = data.get("original")
    if not isinstance(date_value, str) or date_value.strip() == "":
        return False, "extract date requires non-empty date"
    if not isinstance(original, str) or original.strip() == "":
        return False, "extract date requires non-empty original"
    ok, detail = _score_in_unit_interval(data.get("confidence"), "confidence")
    if not ok:
        return False, detail
    return True, None


def _extract_order_number_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status == "failed":
        return True, None
    data = payload.get("data")
    if not isinstance(data, dict):
        return False, "extract order number data must be an object"
    order_number = data.get("orderNumber")
    evidence = data.get("evidence")
    if not isinstance(order_number, str) or order_number.strip() == "":
        return False, "extract order number requires non-empty orderNumber"
    ok, detail = _score_in_unit_interval(data.get("confidence"), "confidence")
    if not ok:
        return False, detail
    if not isinstance(evidence, str) or evidence.strip() == "":
        return False, "extract order number requires non-empty evidence"
    return True, None


def _extract_document_type_business_rules(
    _context: ResultValidationContext,
    payload: dict[str, Any],
) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status == "failed":
        return True, None
    data = payload.get("data")
    if not isinstance(data, dict):
        return False, "extract document type data must be an object"
    document_type = data.get("documentType")
    if not isinstance(document_type, str) or document_type.strip() == "":
        return False, "extract document type requires non-empty documentType"
    ok, detail = _score_in_unit_interval(data.get("confidence"), "confidence")
    if not ok:
        return False, detail
    evidence = data.get("evidence")
    if not isinstance(evidence, list) or len(evidence) == 0:
        return False, "extract document type requires at least one evidence item"
    return True, None


def _default_business_rules(_context: ResultValidationContext, payload: dict[str, Any]) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if status in {"succeeded", "partial"}:
        data = payload.get("data")
        if data is None:
            return False, "successful result requires data"
        if isinstance(data, dict) and not data:
            return False, "successful result data must not be empty"
    return True, None


def _apply_semantic_quality(
    context: ResultValidationContext,
    payload: dict[str, Any],
    prior: ResultValidationOutcome,
) -> ResultValidationOutcome:
    if not prior.valid:
        return prior
    semantic = evaluate_semantic_quality(
        task_type=context.task_type,
        payload=payload,
        task_input=context.task_input,
    )
    if semantic.valid:
        return ResultValidationOutcome(
            valid=True,
            schema_valid=prior.schema_valid,
            business_rules_valid=prior.business_rules_valid,
            semantic_quality_valid=True,
        )
    detail = semantic.detail or "semantic quality check failed"
    if semantic.self_reported_confidence_ignored:
        detail = f"{detail}; self-reported confidence is not sufficient proof"
    return ResultValidationOutcome(
        valid=False,
        schema_valid=prior.schema_valid,
        business_rules_valid=prior.business_rules_valid,
        semantic_quality_valid=False,
        failure_code=semantic.failure_code or "SEMANTIC_QUALITY_FAILED",
        detail=detail,
    )


def _validate_with_schema(
    context: ResultValidationContext,
    payload: dict[str, Any],
    *,
    business_rules: Callable[[ResultValidationContext, dict[str, Any]], tuple[bool, str | None]] | None = None,
) -> ResultValidationOutcome:
    schema = output_schema_for(context.task_type)
    if schema is None:
        ok, detail = _default_business_rules(context, payload)
        if not ok:
            return ResultValidationOutcome(
                valid=False,
                schema_valid=True,
                business_rules_valid=False,
                failure_code="RESULT_VALIDATION_FAILED",
                detail=detail,
            )
        return ResultValidationOutcome(valid=True, schema_valid=True, business_rules_valid=True)

    schema_ok, schema_detail = _validate_json_schema(payload, schema)
    if not schema_ok:
        return ResultValidationOutcome(
            valid=False,
            schema_valid=False,
            business_rules_valid=False,
            failure_code="RESULT_SCHEMA_INVALID",
            detail=schema_detail,
        )

    rules = business_rules or _default_business_rules
    rules_ok, rules_detail = rules(context, payload)
    if not rules_ok:
        return ResultValidationOutcome(
            valid=False,
            schema_valid=True,
            business_rules_valid=False,
            failure_code="RESULT_VALIDATION_FAILED",
            detail=rules_detail,
        )
    return ResultValidationOutcome(valid=True, schema_valid=True, business_rules_valid=True)


def _validate_document_ocr(context: ResultValidationContext, payload: dict[str, Any]) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_document_ocr_business_rules)


def _validate_text_summarize(context: ResultValidationContext, payload: dict[str, Any]) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_text_summarize_business_rules)


def _validate_text_classify(context: ResultValidationContext, payload: dict[str, Any]) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_text_classify_business_rules)


def _validate_moderation_prompt_safety(
    context: ResultValidationContext,
    payload: dict[str, Any],
) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_moderation_prompt_safety_business_rules)


def _validate_moderation_text(context: ResultValidationContext, payload: dict[str, Any]) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_moderation_text_business_rules)


def _validate_moderation_profanity(
    context: ResultValidationContext,
    payload: dict[str, Any],
) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_moderation_profanity_business_rules)


def _validate_moderation_spam_comment(
    context: ResultValidationContext,
    payload: dict[str, Any],
) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_moderation_spam_comment_business_rules)


def _validate_review_fake_detection(
    context: ResultValidationContext,
    payload: dict[str, Any],
) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_review_fake_detection_business_rules)


def _validate_review_sentiment(context: ResultValidationContext, payload: dict[str, Any]) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_review_sentiment_business_rules)


def _validate_review_topic_tagging(
    context: ResultValidationContext,
    payload: dict[str, Any],
) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_review_topic_tagging_business_rules)


def _validate_llm_summary_verification(
    context: ResultValidationContext,
    payload: dict[str, Any],
) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_llm_summary_verification_business_rules)


def _validate_llm_hallucination_check(
    context: ResultValidationContext,
    payload: dict[str, Any],
) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_llm_hallucination_check_business_rules)


def _validate_llm_ocr_output_validation(
    context: ResultValidationContext,
    payload: dict[str, Any],
) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_llm_ocr_output_validation_business_rules)


def _validate_llm_policy_violation(
    context: ResultValidationContext,
    payload: dict[str, Any],
) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_llm_policy_violation_business_rules)


def _validate_llm_prompt_output_consistency(
    context: ResultValidationContext,
    payload: dict[str, Any],
) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_llm_prompt_output_consistency_business_rules)


def _validate_llm_answer_quality_score(
    context: ResultValidationContext,
    payload: dict[str, Any],
) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_llm_answer_quality_score_business_rules)


def _validate_llm_suspicious_output(
    context: ResultValidationContext,
    payload: dict[str, Any],
) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_llm_suspicious_output_business_rules)


def _validate_nlp_language_detection(
    context: ResultValidationContext,
    payload: dict[str, Any],
) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_nlp_language_detection_business_rules)


def _validate_nlp_text_classification(
    context: ResultValidationContext,
    payload: dict[str, Any],
) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_nlp_text_classification_business_rules)


def _validate_nlp_spam_fraud_classification(
    context: ResultValidationContext,
    payload: dict[str, Any],
) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_nlp_spam_fraud_classification_business_rules)


def _validate_ml_bot_abuse_risk(context: ResultValidationContext, payload: dict[str, Any]) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_ml_bot_abuse_risk_business_rules)


def _validate_document_extract(context: ResultValidationContext, payload: dict[str, Any]) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_document_extract_business_rules)


def _validate_extract_amount(context: ResultValidationContext, payload: dict[str, Any]) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_extract_amount_business_rules)


def _validate_extract_date(context: ResultValidationContext, payload: dict[str, Any]) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_extract_date_business_rules)


def _validate_extract_order_number(
    context: ResultValidationContext,
    payload: dict[str, Any],
) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_extract_order_number_business_rules)


def _validate_extract_document_type(
    context: ResultValidationContext,
    payload: dict[str, Any],
) -> ResultValidationOutcome:
    return _validate_with_schema(context, payload, business_rules=_extract_document_type_business_rules)


class ResultValidatorRegistry:
    def __init__(self) -> None:
        self._validators: dict[str, ValidatorFn] = {}
        self._register_defaults()

    def _register_defaults(self) -> None:
        self.register("document.ocr", _validate_document_ocr)
        self.register("text.summarize", _validate_text_summarize)
        self.register("text.classify", _validate_text_classify)
        self.register("moderation.prompt_safety", _validate_moderation_prompt_safety)
        self.register("moderation.text", _validate_moderation_text)
        self.register("moderation.profanity", _validate_moderation_profanity)
        self.register("moderation.spam_comment", _validate_moderation_spam_comment)
        self.register("review.fake_detection", _validate_review_fake_detection)
        self.register("review.sentiment", _validate_review_sentiment)
        self.register("review.topic_tagging", _validate_review_topic_tagging)
        self.register("llm.summary_verification", _validate_llm_summary_verification)
        self.register("llm.hallucination_check", _validate_llm_hallucination_check)
        self.register("llm.ocr_output_validation", _validate_llm_ocr_output_validation)
        self.register("llm.policy_violation", _validate_llm_policy_violation)
        self.register("llm.prompt_output_consistency", _validate_llm_prompt_output_consistency)
        self.register("llm.answer_quality_score", _validate_llm_answer_quality_score)
        self.register("llm.suspicious_output", _validate_llm_suspicious_output)
        self.register("nlp.language_detection", _validate_nlp_language_detection)
        self.register("nlp.text_classification", _validate_nlp_text_classification)
        self.register("nlp.spam_fraud_classification", _validate_nlp_spam_fraud_classification)
        self.register("ml.bot_abuse_risk", _validate_ml_bot_abuse_risk)
        self.register("document.extract", _validate_document_extract)
        self.register("extract.amount", _validate_extract_amount)
        self.register("extract.date", _validate_extract_date)
        self.register("extract.order_number", _validate_extract_order_number)
        self.register("extract.document_type", _validate_extract_document_type)
        from edgemint.results.flex_validators import FLEX_VALIDATORS

        for task_type, validator in FLEX_VALIDATORS.items():
            self.register(task_type, validator)
        from edgemint.results.vision_validators import VISION_VALIDATORS

        for task_type, validator in VISION_VALIDATORS.items():
            self.register(task_type, validator)
        from edgemint.results.gap_validators import GAP_VALIDATORS

        for task_type, validator in GAP_VALIDATORS.items():
            self.register(task_type, validator)

    def register(self, task_type: str, validator: ValidatorFn) -> None:
        self._validators[task_type] = validator

    def validate(self, context: ResultValidationContext) -> ResultValidationOutcome:
        if context.inline_output is None or context.inline_output == "":
            return ResultValidationOutcome(valid=True, schema_valid=True, business_rules_valid=True)
        try:
            envelope = json.loads(context.inline_output)
        except json.JSONDecodeError:
            return ResultValidationOutcome(
                valid=False,
                schema_valid=False,
                business_rules_valid=False,
                failure_code="RESULT_SCHEMA_INVALID",
                detail="inline output must be JSON",
            )
        if not isinstance(envelope, dict):
            return ResultValidationOutcome(
                valid=False,
                schema_valid=False,
                business_rules_valid=False,
                failure_code="RESULT_SCHEMA_INVALID",
                detail="inline output must be an object",
            )
        payload = extract_task_result_payload(envelope)
        validator = self._validators.get(context.task_type)
        if validator is not None:
            outcome = validator(context, payload)
        else:
            generic_context = ResultValidationContext(
                task_type=context.task_type,
                inline_output=context.inline_output,
                task_input=context.task_input,
            )
            outcome = _validate_with_schema(generic_context, payload)
        return _apply_semantic_quality(context, payload, outcome)


_default_registry: ResultValidatorRegistry | None = None


def get_result_validator_registry() -> ResultValidatorRegistry:
    global _default_registry
    if _default_registry is None:
        _default_registry = ResultValidatorRegistry()
    return _default_registry


def validate_task_result(
    *,
    task_type: str,
    inline_output: str | None,
    task_input: dict[str, Any] | None = None,
    registry: ResultValidatorRegistry | None = None,
) -> ResultValidationOutcome:
    active = registry or get_result_validator_registry()
    return active.validate(
        ResultValidationContext(
            task_type=task_type,
            inline_output=inline_output,
            task_input=task_input,
        )
    )
