from __future__ import annotations

from dataclasses import dataclass
from typing import Any

SUPPORTED_SCHEMA_VERSION = "1"

SUPPORTED_BILLING_RULE_IDS = frozenset(
    {
        "pending_not_confirmed_charge",
        "promised_not_completed_refund",
    }
)

BILLING_RULE_DESCRIPTIONS = {
    "pending_not_confirmed_charge": (
        "Do not describe a pending bank authorization as a confirmed charge."
    ),
    "promised_not_completed_refund": (
        "Do not describe a promised refund as already completed."
    ),
}


class SummarizeConstraintsError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class SummarizeTaskConstraintsV1:
    max_summary_words: int | None = None
    key_point_count: int | None = None
    coverage_axes: tuple[str, ...] = ()
    billing_rules: tuple[str, ...] = ()

    @property
    def unchecked_billing_rule_ids(self) -> tuple[str, ...]:
        return self.billing_rules


@dataclass(frozen=True, slots=True)
class SummarizeValidationResult:
    blocking_violations: tuple[str, ...]
    unchecked_coverage_axes: tuple[str, ...] = ()
    unchecked_billing_rule_ids: tuple[str, ...] = ()

    @property
    def passed(self) -> bool:
        return not self.blocking_violations


def count_summary_words(text: str) -> int:
    trimmed = text.strip()
    if not trimmed:
        return 0
    return len([part for part in trimmed.split() if part])


def _positive_int(value: Any, *, field: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise SummarizeConstraintsError(f"{field} must be a positive integer")
    if value <= 0:
        raise SummarizeConstraintsError(f"{field} must be a positive integer")
    return value


def parse_summarize_constraints(raw: dict[str, Any] | None) -> SummarizeTaskConstraintsV1 | None:
    if not raw:
        return None
    version = str(raw.get("schemaVersion", ""))
    if version != SUPPORTED_SCHEMA_VERSION:
        raise SummarizeConstraintsError(
            f"Unsupported summarize schemaVersion: {version or '(missing)'}"
        )

    max_summary_words = raw.get("maxSummaryWords")
    key_point_count = raw.get("keyPointCount")
    parsed_max = (
        _positive_int(max_summary_words, field="maxSummaryWords")
        if max_summary_words is not None
        else None
    )
    parsed_count = (
        _positive_int(key_point_count, field="keyPointCount")
        if key_point_count is not None
        else None
    )

    axes_raw = raw.get("coverageAxes")
    axes: list[str] = []
    if axes_raw is not None:
        if not isinstance(axes_raw, list):
            raise SummarizeConstraintsError("coverageAxes must be an array")
        axes = [str(item).strip() for item in axes_raw if str(item).strip()]

    rules_raw = raw.get("billingRules")
    rules: list[str] = []
    if rules_raw is not None:
        if not isinstance(rules_raw, list):
            raise SummarizeConstraintsError("billingRules must be an array")
        for item in rules_raw:
            rule_id = str(item).strip()
            if not rule_id:
                continue
            if rule_id not in SUPPORTED_BILLING_RULE_IDS:
                raise SummarizeConstraintsError(f"Unknown billingRules id: {rule_id}")
            rules.append(rule_id)

    return SummarizeTaskConstraintsV1(
        max_summary_words=parsed_max,
        key_point_count=parsed_count,
        coverage_axes=tuple(axes),
        billing_rules=tuple(rules),
    )


def summarize_constraints_from_manifest(manifest: dict[str, Any] | None) -> SummarizeTaskConstraintsV1 | None:
    if manifest is None:
        return None
    options = manifest.get("options")
    if not isinstance(options, dict):
        return None
    summarize = options.get("summarize")
    if not isinstance(summarize, dict):
        return None
    return parse_summarize_constraints(summarize)


def _normalize_whitespace(value: str) -> str:
    return " ".join(value.strip().split())


def _normalize_string_list(raw: Any) -> list[str] | Any:
    if not isinstance(raw, list):
        return raw
    seen: set[str] = set()
    result: list[str] = []
    for item in raw:
        if not isinstance(item, str):
            continue
        cleaned = _normalize_whitespace(item)
        if not cleaned:
            continue
        key = cleaned.lower()
        if key in seen:
            continue
        seen.add(key)
        result.append(cleaned)
    return result


DEFAULT_TEXT_SUMMARIZE_PORTAL_OPTIONS: dict[str, Any] = {
    "schemaVersion": "1",
    "maxSummaryWords": 80,
    "keyPointCount": 5,
    "coverageAxes": ["delivery", "tracking", "product", "billing", "support"],
    "billingRules": ["pending_not_confirmed_charge", "promised_not_completed_refund"],
}


def default_text_summarize_portal_options() -> dict[str, Any]:
    return dict(DEFAULT_TEXT_SUMMARIZE_PORTAL_OPTIONS)


def normalize_summarize_data(data: dict[str, Any]) -> dict[str, Any]:
    return {
        "summary": data.get("summary")
        if not isinstance(data.get("summary"), str)
        else _normalize_whitespace(data["summary"]),
        "keyPoints": _normalize_string_list(data.get("keyPoints")),
        "mainComplaint": data.get("mainComplaint")
        if not isinstance(data.get("mainComplaint"), str)
        else _normalize_whitespace(data["mainComplaint"]),
        "suggestedImprovement": data.get("suggestedImprovement")
        if not isinstance(data.get("suggestedImprovement"), str)
        else _normalize_whitespace(data["suggestedImprovement"]),
        "missingOrUnclear": _normalize_string_list(data.get("missingOrUnclear")),
    }


def validate_summarize_data(
    data: dict[str, Any],
    constraints: SummarizeTaskConstraintsV1 | None = None,
) -> SummarizeValidationResult:
    violations: list[str] = []

    for field in ("summary", "mainComplaint", "suggestedImprovement"):
        value = data.get(field)
        if not isinstance(value, str) or not value.strip():
            violations.append(f"{field} must be a non-empty string")

    key_points = data.get("keyPoints")
    if not isinstance(key_points, list):
        violations.append("keyPoints must be an array")
    else:
        seen: set[str] = set()
        for index, item in enumerate(key_points):
            if not isinstance(item, str):
                violations.append(f"keyPoints[{index}] must be a string")
                continue
            if not item.strip():
                violations.append(f"keyPoints[{index}] must not be empty")
            key = _normalize_whitespace(item).lower()
            if key in seen:
                violations.append("keyPoints contains duplicate entries")
            seen.add(key)

    missing = data.get("missingOrUnclear")
    if not isinstance(missing, list):
        violations.append("missingOrUnclear must be an array")
    else:
        seen_missing: set[str] = set()
        for index, item in enumerate(missing):
            if not isinstance(item, str):
                violations.append(f"missingOrUnclear[{index}] must be a string")
                continue
            if not item.strip():
                violations.append(f"missingOrUnclear[{index}] must not be empty")
            key = _normalize_whitespace(item).lower()
            if key in seen_missing:
                violations.append("missingOrUnclear contains duplicate entries")
            seen_missing.add(key)

    if constraints is not None:
        summary = data.get("summary")
        if constraints.max_summary_words is not None and isinstance(summary, str):
            words = count_summary_words(summary)
            if words > constraints.max_summary_words:
                violations.append(
                    f"summary exceeds maxSummaryWords ({words} > {constraints.max_summary_words})"
                )
        if constraints.key_point_count is not None and isinstance(key_points, list):
            string_points = [item for item in key_points if isinstance(item, str)]
            if len(string_points) != constraints.key_point_count:
                violations.append(
                    "keyPoints count "
                    f"{len(string_points)} != keyPointCount {constraints.key_point_count}"
                )

    return SummarizeValidationResult(
        blocking_violations=tuple(violations),
        unchecked_coverage_axes=constraints.coverage_axes if constraints else (),
        unchecked_billing_rule_ids=constraints.unchecked_billing_rule_ids if constraints else (),
    )
