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


def _ocr_family_rules(_ctx: ResultValidationContext, payload: dict[str, Any]) -> tuple[bool, str | None]:
    from edgemint.results.validator import _document_ocr_business_rules

    return _document_ocr_business_rules(_ctx, payload)


def _quality_document_image_rules(_ctx: ResultValidationContext, payload: dict[str, Any]) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if _failed_ok(status):
        return True, None
    data, err = _require_data(payload, "document image quality")
    if err[0] is False:
        return err
    ok, detail = _score_in_unit_interval(data.get("score"), "score")
    if not ok:
        return False, detail
    for field in ("brightness", "contrast", "sharpness", "clippedRatio"):
        if not isinstance(data.get(field), (int, float)):
            return False, f"document image quality {field} must be numeric"
    if not isinstance(data.get("acceptable"), bool):
        return False, "document image quality requires boolean acceptable"
    return True, None


def _quality_blurry_image_rules(_ctx: ResultValidationContext, payload: dict[str, Any]) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if _failed_ok(status):
        return True, None
    data, err = _require_data(payload, "blurry image")
    if err[0] is False:
        return err
    variance = data.get("laplacianVariance")
    if not isinstance(variance, (int, float)) or float(variance) < 0:
        return False, "blurry image laplacianVariance must be a non-negative number"
    if not isinstance(data.get("blurry"), bool):
        return False, "blurry image requires boolean blurry"
    threshold = data.get("threshold")
    if not isinstance(threshold, (int, float)) or float(threshold) < 0:
        return False, "blurry image threshold must be a non-negative number"
    return True, None


def _duplicate_image_rules(_ctx: ResultValidationContext, payload: dict[str, Any]) -> tuple[bool, str | None]:
    status = str(payload.get("status", "")).lower()
    if _failed_ok(status):
        return True, None
    data, err = _require_data(payload, "duplicate image")
    if err[0] is False:
        return err
    distance = data.get("hammingDistance")
    if not isinstance(distance, int) or distance < 0:
        return False, "duplicate image hammingDistance must be a non-negative integer"
    ok, detail = _score_in_unit_interval(data.get("similarity"), "similarity")
    if not ok:
        return False, detail
    if not isinstance(data.get("duplicate"), bool):
        return False, "duplicate image requires boolean duplicate"
    algorithm = data.get("algorithm")
    if not isinstance(algorithm, str) or algorithm.strip() == "":
        return False, "duplicate image algorithm must be a non-empty string"
    return True, None


def _make_validator(rules: Callable[[ResultValidationContext, dict[str, Any]], tuple[bool, str | None]]) -> ValidatorFn:
    def validate(context: ResultValidationContext, payload: dict[str, Any]) -> ResultValidationOutcome:
        from edgemint.results.validator import _validate_with_schema

        return _validate_with_schema(context, payload, business_rules=rules)

    return validate


GAP_VALIDATORS: dict[str, ValidatorFn] = {
    "ocr.receipt": _make_validator(_ocr_family_rules),
    "ocr.invoice": _make_validator(_ocr_family_rules),
    "ocr.simple_form": _make_validator(_ocr_family_rules),
    "ocr.product_label": _make_validator(_ocr_family_rules),
    "quality.document_image": _make_validator(_quality_document_image_rules),
    "quality.blurry_image": _make_validator(_quality_blurry_image_rules),
    "catalog.duplicate_image": _make_validator(_duplicate_image_rules),
}
