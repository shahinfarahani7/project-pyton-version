from __future__ import annotations

from dataclasses import dataclass

from edgemint.verification.engine import VerificationEvidence, compute_confidence_milli


@dataclass(frozen=True, slots=True)
class GoldenExpectation:
    task_type: str
    expected_result_sha256: str
    minimum_confidence_milli: int = 960


def evaluate_golden_task(
    evidence: VerificationEvidence,
    expectation: GoldenExpectation,
) -> dict[str, str]:
    confidence = compute_confidence_milli(evidence)
    if evidence.result_sha256 != expectation.expected_result_sha256:
        return {"status": "failed", "reason": "result_mismatch"}
    if confidence < expectation.minimum_confidence_milli:
        return {"status": "failed", "reason": "confidence_below_trap_threshold"}
    return {"status": "passed", "reason": "golden_task_ok"}
