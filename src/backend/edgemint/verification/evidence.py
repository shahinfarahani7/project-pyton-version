from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any


@dataclass(frozen=True, slots=True)
class DecisionEvidence:
    evidence_id: str
    result_id: str
    task_id: str
    attempt_id: str
    assignment_id: str
    policy_version: str
    strategy: str
    outcome: str
    confidence_milli: int | None
    reason: str
    inputs_digest: str
    recorded_at: datetime

    def to_dict(self) -> dict[str, Any]:
        return {
            "evidenceId": self.evidence_id,
            "resultId": self.result_id,
            "taskId": self.task_id,
            "attemptId": self.attempt_id,
            "assignmentId": self.assignment_id,
            "policyVersion": self.policy_version,
            "strategy": self.strategy,
            "outcome": self.outcome,
            "confidenceMilli": self.confidence_milli,
            "reason": self.reason,
            "inputsDigest": self.inputs_digest,
            "recordedAt": self.recorded_at.isoformat(),
            "immutable": True,
        }


def build_inputs_digest(*, evidence: dict[str, Any]) -> str:
    return hashlib.sha256(json.dumps(evidence, sort_keys=True).encode("utf-8")).hexdigest()


def record_decision_evidence(
    *,
    evidence_id: str,
    result_id: str,
    task_id: str,
    attempt_id: str,
    assignment_id: str,
    decision: dict[str, Any],
    source_evidence: dict[str, Any],
) -> DecisionEvidence:
    return DecisionEvidence(
        evidence_id=evidence_id,
        result_id=result_id,
        task_id=task_id,
        attempt_id=attempt_id,
        assignment_id=assignment_id,
        policy_version=str(decision.get("policyVersion", "unknown")),
        strategy=str(decision["strategy"]),
        outcome=str(decision["outcome"]),
        confidence_milli=decision.get("confidenceMilli"),
        reason=str(decision.get("reason", "")),
        inputs_digest=build_inputs_digest(evidence=source_evidence),
        recorded_at=datetime.now(UTC),
    )
