from __future__ import annotations

from edgemint.routing.quality_escalation import escalated_verification_tier
from edgemint.routing.service import RouterService


def test_quality_failure_escalates_verification_tier() -> None:
    assert escalated_verification_tier(current_tier="standard", failure_code="RESULT_VALIDATION_FAILED") == "high"
    assert escalated_verification_tier(current_tier="high", failure_code="OCR_EMPTY_RESULT") == "premium"
    assert escalated_verification_tier(current_tier="premium", failure_code="VISION_LOW_CONFIDENCE") == "premium"


def test_non_quality_failure_does_not_escalate() -> None:
    assert escalated_verification_tier(current_tier="standard", failure_code="MODEL_UNAVAILABLE") == "standard"


def test_router_service_escalation_hook() -> None:
    router = RouterService()
    tier = router.escalated_verification_tier_for_failure(
        current_tier="standard",
        failure_code="GOLDEN_VALIDATION_FAILED",
    )
    assert tier == "high"
