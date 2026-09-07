"""Bounded input decode admission (Architecture v2 §28, §31, A21/T21)."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path
from typing import Any

import yaml

DEFAULT_POLICY_PATH = (
    Path(__file__).resolve().parents[4]
    / "dsl"
    / "policies"
    / "data"
    / "input-decode-privacy-v1.yaml"
)


class DecodeFailureReason(StrEnum):
    ADMITTED = "ADMITTED"
    DECODE_BOUNDS_EXCEEDED = "DECODE_BOUNDS_EXCEEDED"
    UNSUPPORTED_CONTENT_TYPE = "UNSUPPORTED_CONTENT_TYPE"


@dataclass(frozen=True, slots=True)
class DecodeAdmissionDecision:
    permitted: bool
    reason_code: DecodeFailureReason
    estimated_decoded_bytes: int
    detail: str | None = None


def load_input_decode_privacy_policy(path: Path | None = None) -> dict[str, Any]:
    policy_path = path or DEFAULT_POLICY_PATH
    raw = yaml.safe_load(policy_path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError(f"invalid input decode privacy policy: {policy_path}")
    return raw


def estimate_decoded_bytes(
    *,
    content_type: str,
    compressed_bytes: int,
    page_count: int = 1,
    image_width: int = 0,
    image_height: int = 0,
    policy: dict[str, Any] | None = None,
) -> int:
    """Estimate decoded memory demand; compressed size alone is insufficient."""
    loaded = policy or load_input_decode_privacy_policy()
    bounds = loaded.get("decodeBounds") or {}
    normalized = content_type.split(";", 1)[0].strip().lower()
    compressed = max(0, int(compressed_bytes))
    pages = max(1, int(page_count))

    if normalized == "application/pdf":
        factor = int(bounds.get("pdfExpansionFactor", 10))
        page_estimate = pages * 1024 * 1024 * 4
        return max(compressed * factor, page_estimate)

    if normalized.startswith("image/"):
        if image_width > 0 and image_height > 0:
            return image_width * image_height * 4
        factor = int(bounds.get("imageExpansionFactor", 4))
        return compressed * factor

    factor = int(bounds.get("defaultExpansionFactor", 3))
    return compressed * factor


def evaluate_decode_admission(
    *,
    content_type: str,
    compressed_bytes: int,
    page_count: int = 1,
    image_width: int = 0,
    image_height: int = 0,
    policy: dict[str, Any] | None = None,
) -> DecodeAdmissionDecision:
    loaded = policy or load_input_decode_privacy_policy()
    bounds = loaded.get("decodeBounds") or {}
    max_decoded = int(bounds.get("maxDecodedBytes", 0))
    max_pages = int(bounds.get("maxPdfPages", 0))
    max_pixels = int(bounds.get("maxImagePixels", 0))

    if max_decoded <= 0:
        return DecodeAdmissionDecision(
            permitted=False,
            reason_code=DecodeFailureReason.DECODE_BOUNDS_EXCEEDED,
            estimated_decoded_bytes=0,
            detail="missing decode bounds policy blocks admission",
        )

    normalized = content_type.split(";", 1)[0].strip().lower()
    if normalized == "application/pdf" and page_count > max_pages:
        return DecodeAdmissionDecision(
            permitted=False,
            reason_code=DecodeFailureReason.DECODE_BOUNDS_EXCEEDED,
            estimated_decoded_bytes=0,
            detail=f"pdf page count {page_count} exceeds cap {max_pages}",
        )

    if normalized.startswith("image/") and image_width > 0 and image_height > 0:
        pixels = image_width * image_height
        if pixels > max_pixels:
            return DecodeAdmissionDecision(
                permitted=False,
                reason_code=DecodeFailureReason.DECODE_BOUNDS_EXCEEDED,
                estimated_decoded_bytes=pixels * 4,
                detail=f"image pixels {pixels} exceed cap {max_pixels}",
            )

    estimated = estimate_decoded_bytes(
        content_type=content_type,
        compressed_bytes=compressed_bytes,
        page_count=page_count,
        image_width=image_width,
        image_height=image_height,
        policy=loaded,
    )
    if estimated > max_decoded:
        return DecodeAdmissionDecision(
            permitted=False,
            reason_code=DecodeFailureReason.DECODE_BOUNDS_EXCEEDED,
            estimated_decoded_bytes=estimated,
            detail=f"estimated decoded bytes {estimated} exceed cap {max_decoded}",
        )

    return DecodeAdmissionDecision(
        permitted=True,
        reason_code=DecodeFailureReason.ADMITTED,
        estimated_decoded_bytes=estimated,
    )
