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


def _require_non_empty_string(value: object, field_name: str) -> tuple[bool, str | None]:
    if not isinstance(value, str) or value.strip() == "":
        return False, f"{field_name} must be a non-empty string"
    return True, None


def _require_string_array(value: object, field_name: str) -> tuple[bool, str | None]:
    if not isinstance(value, list):
        return False, f"{field_name} must be an array"
    return True, None


def _image_classify_rules(_ctx: ResultValidationContext, payload: dict[str, Any]) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if _failed_ok(status):
        return True, None
    data, err = _require_data(payload, "image classify")
    if err[0] is False:
        return err
    ok, detail = _require_non_empty_string(data.get("label"), "label")
    if not ok:
        return False, detail
    ok, detail = _score_in_unit_interval(data.get("confidence"), "confidence")
    if not ok:
        return False, detail
    evidence = data.get("evidence")
    if not isinstance(evidence, list) or len(evidence) == 0:
        return False, "image classify evidence must be a non-empty array"
    return True, None


def _risk_flag_rules(
    *,
    flag_field: str,
    array_field: str,
    label: str,
) -> Callable[[ResultValidationContext, dict[str, Any]], tuple[bool, str | None]]:
    def validate(_ctx: ResultValidationContext, payload: dict[str, Any]) -> tuple[bool, str | None]:
        status = str(payload.get("status", "")).lower()
        if _failed_ok(status):
            return True, None
        data, err = _require_data(payload, label)
        if err[0] is False:
            return err
        if not isinstance(data.get(flag_field), bool):
            return False, f"{label} requires boolean {flag_field}"
        ok, detail = _score_in_unit_interval(data.get("riskScore"), "riskScore")
        if not ok:
            return False, detail
        ok, detail = _require_string_array(data.get(array_field), array_field)
        if not ok:
            return False, detail
        ok, detail = _require_non_empty_string(data.get("reason"), "reason")
        if not ok:
            return False, detail
        if data[flag_field] and len(data[array_field]) == 0:
            return False, f"{label} {array_field} required when {flag_field} is true"
        return True, None

    return validate


def _safe_image_rules(_ctx: ResultValidationContext, payload: dict[str, Any]) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if _failed_ok(status):
        return True, None
    data, err = _require_data(payload, "unsafe image")
    if err[0] is False:
        return err
    if not isinstance(data.get("safe"), bool):
        return False, "unsafe image requires boolean safe"
    ok, detail = _score_in_unit_interval(data.get("riskScore"), "riskScore")
    if not ok:
        return False, detail
    ok, detail = _require_string_array(data.get("categories"), "categories")
    if not ok:
        return False, detail
    ok, detail = _require_non_empty_string(data.get("reason"), "reason")
    if not ok:
        return False, detail
    if not data["safe"] and len(data["categories"]) == 0:
        return False, "unsafe image categories required when safe is false"
    return True, None


def _allowed_moderation_rules(
    *,
    array_field: str,
    label: str,
) -> Callable[[ResultValidationContext, dict[str, Any]], tuple[bool, str | None]]:
    def validate(_ctx: ResultValidationContext, payload: dict[str, Any]) -> tuple[bool, str | None]:
        status = str(payload.get("status", "")).lower()
        if _failed_ok(status):
            return True, None
        data, err = _require_data(payload, label)
        if err[0] is False:
            return err
        if not isinstance(data.get("allowed"), bool):
            return False, f"{label} requires boolean allowed"
        ok, detail = _score_in_unit_interval(data.get("riskScore"), "riskScore")
        if not ok:
            return False, detail
        ok, detail = _require_string_array(data.get(array_field), array_field)
        if not ok:
            return False, detail
        ok, detail = _require_non_empty_string(data.get("reason"), "reason")
        if not ok:
            return False, detail
        if not data["allowed"] and len(data[array_field]) == 0:
            return False, f"{label} {array_field} required when allowed is false"
        return True, None

    return validate


def _image_tagging_rules(_ctx: ResultValidationContext, payload: dict[str, Any]) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if _failed_ok(status):
        return True, None
    data, err = _require_data(payload, "image tagging")
    if err[0] is False:
        return err
    tags = data.get("tags")
    if not isinstance(tags, list) or len(tags) == 0:
        return False, "image tagging tags must be a non-empty array"
    ok, detail = _score_in_unit_interval(data.get("confidence"), "confidence")
    if not ok:
        return False, detail
    evidence = data.get("evidence")
    if not isinstance(evidence, list) or len(evidence) == 0:
        return False, "image tagging evidence must be a non-empty array"
    return True, None


def _product_classification_rules(_ctx: ResultValidationContext, payload: dict[str, Any]) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if _failed_ok(status):
        return True, None
    data, err = _require_data(payload, "product classification")
    if err[0] is False:
        return err
    ok, detail = _require_non_empty_string(data.get("category"), "category")
    if not ok:
        return False, detail
    ok, detail = _score_in_unit_interval(data.get("confidence"), "confidence")
    if not ok:
        return False, detail
    ok, detail = _require_string_array(data.get("alternatives"), "alternatives")
    if not ok:
        return False, detail
    return True, None


def _product_quality_score_rules(_ctx: ResultValidationContext, payload: dict[str, Any]) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if _failed_ok(status):
        return True, None
    data, err = _require_data(payload, "product quality score")
    if err[0] is False:
        return err
    ok, detail = _score_in_unit_interval(data.get("score"), "score")
    if not ok:
        return False, detail
    ok, detail = _require_string_array(data.get("issues"), "issues")
    if not ok:
        return False, detail
    recommendations = data.get("recommendations")
    if not isinstance(recommendations, list) or len(recommendations) == 0:
        return False, "product quality score recommendations must be a non-empty array"
    return True, None


def _brand_logo_rules(_ctx: ResultValidationContext, payload: dict[str, Any]) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if _failed_ok(status):
        return True, None
    data, err = _require_data(payload, "brand logo")
    if err[0] is False:
        return err
    if not isinstance(data.get("detected"), bool):
        return False, "brand logo requires boolean detected"
    ok, detail = _require_string_array(data.get("brands"), "brands")
    if not ok:
        return False, detail
    ok, detail = _score_in_unit_interval(data.get("confidence"), "confidence")
    if not ok:
        return False, detail
    ok, detail = _require_string_array(data.get("evidence"), "evidence")
    if not ok:
        return False, detail
    if data["detected"] and len(data["brands"]) == 0:
        return False, "brand logo brands required when detected is true"
    return True, None


def _remove_background_rules(_ctx: ResultValidationContext, payload: dict[str, Any]) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if _failed_ok(status):
        return True, None
    data, err = _require_data(payload, "remove background")
    if err[0] is False:
        return err
    ok, detail = _require_non_empty_string(data.get("mimeType"), "mimeType")
    if not ok:
        return False, detail
    ok, detail = _require_non_empty_string(data.get("imageBase64"), "imageBase64")
    if not ok:
        return False, detail
    size_bytes = data.get("sizeBytes")
    if not isinstance(size_bytes, int) or size_bytes < 1:
        return False, "remove background sizeBytes must be a positive integer"
    ok, detail = _require_non_empty_string(data.get("segmentationModel"), "segmentationModel")
    if not ok:
        return False, detail
    return True, None


def _make_validator(rules: Callable[[ResultValidationContext, dict[str, Any]], tuple[bool, str | None]]) -> ValidatorFn:
    def validate(context: ResultValidationContext, payload: dict[str, Any]) -> ResultValidationOutcome:
        from edgemint.results.validator import _validate_with_schema

        return _validate_with_schema(context, payload, business_rules=rules)

    return validate


VISION_VALIDATORS: dict[str, ValidatorFn] = {
    "image.classify": _make_validator(_image_classify_rules),
    "safety.nsfw_detection": _make_validator(
        _risk_flag_rules(flag_field="nsfw", array_field="categories", label="nsfw detection")
    ),
    "safety.violence_detection": _make_validator(
        _risk_flag_rules(flag_field="violence", array_field="categories", label="violence detection")
    ),
    "safety.weapon_detection": _make_validator(
        _risk_flag_rules(flag_field="weapon", array_field="types", label="weapon detection")
    ),
    "safety.unsafe_image": _make_validator(_safe_image_rules),
    "moderation.profile_image": _make_validator(
        _allowed_moderation_rules(array_field="issues", label="profile image moderation")
    ),
    "moderation.generated_image": _make_validator(
        _allowed_moderation_rules(array_field="categories", label="generated image moderation")
    ),
    "catalog.image_tagging": _make_validator(_image_tagging_rules),
    "catalog.product_classification": _make_validator(_product_classification_rules),
    "catalog.product_quality_score": _make_validator(_product_quality_score_rules),
    "catalog.brand_logo": _make_validator(_brand_logo_rules),
    "catalog.prohibited_product": _make_validator(
        _risk_flag_rules(flag_field="prohibited", array_field="categories", label="prohibited product")
    ),
    "llm.image_output_safety": _make_validator(_safe_image_rules),
    "image.remove_background": _make_validator(_remove_background_rules),
}
