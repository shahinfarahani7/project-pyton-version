from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from typing import Any

from edgemint.verification.policy import VerificationPolicy


@dataclass(frozen=True, slots=True)
class VerificationEvidence:
    task_type: str
    verification_level: str
    result_sha256: str
    schema_valid: bool
    artifact_checksum_valid: bool
    worker_signature_valid: bool
    business_rules_valid: bool
    is_golden_task: bool
    policy_version: str


def compute_confidence_milli(evidence: VerificationEvidence) -> int:
    payload = {
        "artifactChecksumValid": evidence.artifact_checksum_valid,
        "businessRulesValid": evidence.business_rules_valid,
        "isGoldenTask": evidence.is_golden_task,
        "policyVersion": evidence.policy_version,
        "resultSha256": evidence.result_sha256,
        "schemaValid": evidence.schema_valid,
        "taskType": evidence.task_type,
        "verificationLevel": evidence.verification_level,
        "workerSignatureValid": evidence.worker_signature_valid,
    }
    digest = hashlib.sha256(json.dumps(payload, sort_keys=True).encode("utf-8")).hexdigest()
    return 700 + (int(digest[:8], 16) % 301)


def evaluate_automatic_verification(
    evidence: VerificationEvidence,
    *,
    policy: VerificationPolicy | None = None,
) -> dict[str, Any]:
    active = policy or VerificationPolicy.load()
    profile = active.profile(evidence.task_type)
    confidence = compute_confidence_milli(evidence)
    minimum = int(profile["confidence"]["minimumMilli"])
    automatic_accept = int(profile["confidence"]["automaticAcceptMilli"])

    if not all(
        [
            evidence.schema_valid,
            evidence.artifact_checksum_valid,
            evidence.worker_signature_valid,
            evidence.business_rules_valid,
        ]
    ):
        return _decision("rejected", confidence, "required_step_failed", policy_version=active.path.name)

    if evidence.is_golden_task and confidence < automatic_accept:
        return _decision("rejected", confidence, "golden_task_failed", policy_version=active.path.name)

    consensus_required = evidence.verification_level in profile["consensus"]["requiredFor"]
    if consensus_required:
        return _decision("consensus", confidence, "consensus_required", policy_version=active.path.name)

    if confidence < minimum:
        return _decision("retry", confidence, "below_minimum_confidence", policy_version=active.path.name)

    if confidence < automatic_accept:
        if profile.get("failureOutcome") == "retry_then_escalate":
            return _decision(
                "human_review",
                confidence,
                "confidence_escalation",
                policy_version=active.path.name,
            )
        return _decision(
            "accepted_with_warning",
            confidence,
            "below_automatic_accept",
            policy_version=active.path.name,
        )

    return _decision("accepted", confidence, "automatic_accept", policy_version=active.path.name)


def _decision(outcome: str, confidence_milli: int, reason: str, *, policy_version: str) -> dict[str, Any]:
    return {
        "outcome": outcome,
        "confidenceMilli": confidence_milli,
        "reason": reason,
        "policyVersion": policy_version,
        "strategy": "automatic",
        "deterministic": True,
    }
