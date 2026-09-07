from __future__ import annotations

from typing import Any, Callable

from edgemint.results.validator import ResultValidationContext, ResultValidationOutcome, ValidatorFn


def _score_in_unit_interval(value: object, field_name: str) -> tuple[bool, str | None]:
    if not isinstance(value, (int, float)) or float(value) < 0 or float(value) > 1:
        return False, f"{field_name} must be between 0 and 1"
    return True, None


def _failed_ok(status: str) -> bool:
    return status == "failed"


def _require_data(payload: dict[str, Any], label: str) -> tuple[dict[str, Any] | None, tuple[bool, str | None]]:
    data = payload.get("data")
    if not isinstance(data, dict):
        return None, (False, f"{label} data must be an object")
    return data, (True, None)


def _catalog_fake_listing_rules(_ctx: ResultValidationContext, payload: dict[str, Any]) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if _failed_ok(status):
        return True, None
    data, err = _require_data(payload, "fake listing")
    if err[0] is False:
        return err
    if not isinstance(data.get("fake"), bool):
        return False, "fake listing requires boolean fake"
    ok, detail = _score_in_unit_interval(data.get("riskScore"), "riskScore")
    if not ok:
        return False, detail
    reasons = data.get("reasons")
    if not isinstance(reasons, list):
        return False, "fake listing reasons must be an array"
    if data["fake"] and len(reasons) == 0:
        return False, "fake listing reasons required when fake is true"
    return True, None


def _llm_ai_tag_validation_rules(_ctx: ResultValidationContext, payload: dict[str, Any]) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if _failed_ok(status):
        return True, None
    data, err = _require_data(payload, "ai tag validation")
    if err[0] is False:
        return err
    for field in ("validTags", "rejectedTags", "reasons"):
        if not isinstance(data.get(field), list):
            return False, f"ai tag validation {field} must be an array"
    ok, detail = _score_in_unit_interval(data.get("score"), "score")
    if not ok:
        return False, detail
    return True, None


def _llm_caption_validation_rules(_ctx: ResultValidationContext, payload: dict[str, Any]) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if _failed_ok(status):
        return True, None
    data, err = _require_data(payload, "caption validation")
    if err[0] is False:
        return err
    if not isinstance(data.get("valid"), bool):
        return False, "caption validation requires boolean valid"
    ok, detail = _score_in_unit_interval(data.get("score"), "score")
    if not ok:
        return False, detail
    if not isinstance(data.get("issues"), list):
        return False, "caption validation issues must be an array"
    if not isinstance(data.get("suggestedCaption"), str):
        return False, "caption validation suggestedCaption must be a string"
    return True, None


def _dataset_label_verification_rules(_ctx: ResultValidationContext, payload: dict[str, Any]) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if _failed_ok(status):
        return True, None
    data, err = _require_data(payload, "label verification")
    if err[0] is False:
        return err
    if not isinstance(data.get("valid"), bool):
        return False, "label verification requires boolean valid"
    if not isinstance(data.get("correctedLabel"), str):
        return False, "label verification correctedLabel must be a string"
    ok, detail = _score_in_unit_interval(data.get("confidence"), "confidence")
    if not ok:
        return False, detail
    if not isinstance(data.get("reasons"), list):
        return False, "label verification reasons must be an array"
    return True, None


def _dataset_duplicate_cleanup_rules(_ctx: ResultValidationContext, payload: dict[str, Any]) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if _failed_ok(status):
        return True, None
    data, err = _require_data(payload, "duplicate cleanup")
    if err[0] is False:
        return err
    for field in ("duplicateGroups", "keepIds", "removeIds"):
        if not isinstance(data.get(field), list):
            return False, f"duplicate cleanup {field} must be an array"
    return True, None


def _dataset_low_quality_removal_rules(_ctx: ResultValidationContext, payload: dict[str, Any]) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if _failed_ok(status):
        return True, None
    data, err = _require_data(payload, "low quality removal")
    if err[0] is False:
        return err
    if not isinstance(data.get("acceptedIds"), list):
        return False, "low quality removal acceptedIds must be an array"
    if not isinstance(data.get("rejected"), list):
        return False, "low quality removal rejected must be an array"
    ok, detail = _score_in_unit_interval(data.get("threshold"), "threshold")
    if not ok:
        return False, detail
    return True, None


def _ml_active_learning_prelabel_rules(_ctx: ResultValidationContext, payload: dict[str, Any]) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if _failed_ok(status):
        return True, None
    data, err = _require_data(payload, "active learning prelabel")
    if err[0] is False:
        return err
    label = data.get("label")
    if not isinstance(label, str) or label.strip() == "":
        return False, "active learning prelabel requires non-empty label"
    ok, detail = _score_in_unit_interval(data.get("confidence"), "confidence")
    if not ok:
        return False, detail
    if not isinstance(data.get("needsHumanReview"), bool):
        return False, "active learning prelabel requires boolean needsHumanReview"
    evidence = data.get("evidence")
    if not isinstance(evidence, list) or len(evidence) == 0:
        return False, "active learning prelabel requires at least one evidence item"
    return True, None


def _ml_consensus_label_validation_rules(_ctx: ResultValidationContext, payload: dict[str, Any]) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if _failed_ok(status):
        return True, None
    data, err = _require_data(payload, "consensus label validation")
    if err[0] is False:
        return err
    consensus = data.get("consensusLabel")
    if not isinstance(consensus, str) or consensus.strip() == "":
        return False, "consensus label validation requires non-empty consensusLabel"
    ok, detail = _score_in_unit_interval(data.get("agreementScore"), "agreementScore")
    if not ok:
        return False, detail
    if not isinstance(data.get("disputed"), bool):
        return False, "consensus label validation requires boolean disputed"
    reason = data.get("reason")
    if not isinstance(reason, str) or reason.strip() == "":
        return False, "consensus label validation requires non-empty reason"
    return True, None


def _ml_human_verification_quality_rules(_ctx: ResultValidationContext, payload: dict[str, Any]) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if _failed_ok(status):
        return True, None
    data, err = _require_data(payload, "human verification quality")
    if err[0] is False:
        return err
    if not isinstance(data.get("valid"), bool):
        return False, "human verification quality requires boolean valid"
    ok, detail = _score_in_unit_interval(data.get("qualityScore"), "qualityScore")
    if not ok:
        return False, detail
    if not isinstance(data.get("issues"), list):
        return False, "human verification quality issues must be an array"
    recommendation = data.get("recommendation")
    if not isinstance(recommendation, str) or recommendation.strip() == "":
        return False, "human verification quality requires non-empty recommendation"
    return True, None


def _make_validator(rules: Callable[[ResultValidationContext, dict[str, Any]], tuple[bool, str | None]]) -> ValidatorFn:
    def validate(context: ResultValidationContext, payload: dict[str, Any]) -> ResultValidationOutcome:
        from edgemint.results.validator import _validate_with_schema

        return _validate_with_schema(context, payload, business_rules=rules)

    return validate


FLEX_VALIDATORS: dict[str, ValidatorFn] = {
    "catalog.fake_listing": _make_validator(_catalog_fake_listing_rules),
    "llm.ai_tag_validation": _make_validator(_llm_ai_tag_validation_rules),
    "llm.caption_validation": _make_validator(_llm_caption_validation_rules),
    "dataset.label_verification": _make_validator(_dataset_label_verification_rules),
    "dataset.duplicate_cleanup": _make_validator(_dataset_duplicate_cleanup_rules),
    "dataset.low_quality_removal": _make_validator(_dataset_low_quality_removal_rules),
    "ml.active_learning_prelabel": _make_validator(_ml_active_learning_prelabel_rules),
    "ml.consensus_label_validation": _make_validator(_ml_consensus_label_validation_rules),
    "ml.human_verification_quality": _make_validator(_ml_human_verification_quality_rules),
}
