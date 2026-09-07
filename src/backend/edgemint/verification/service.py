from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any
from uuid import uuid4

from edgemint.building_blocks.settings import Settings, get_settings
from edgemint.results.intake import (
    AssignmentBinding,
    ResultSubmission,
    encrypted_storage_reference,
    validate_submission_bindings,
)
from edgemint.results.validator import validate_task_result
from edgemint.verification.consensus import ConsensusVote, evaluate_consensus
from edgemint.verification.engine import VerificationEvidence, evaluate_automatic_verification
from edgemint.verification.evidence import record_decision_evidence
from edgemint.verification.golden import GoldenExpectation, evaluate_golden_task
from edgemint.verification.human_review import HumanReviewQueue
from edgemint.verification.lineage import build_dispute_lineage
from edgemint.verification.policy import VerificationPolicy


@dataclass
class VerificationService:
    settings: Settings = field(default_factory=get_settings)
    policy: VerificationPolicy = field(default_factory=VerificationPolicy.load)
    human_review_queue: HumanReviewQueue = field(default_factory=HumanReviewQueue)
    stored_results: dict[str, set[str]] = field(default_factory=dict)
    decision_records: list[dict[str, Any]] = field(default_factory=list)

    def intake_and_verify(
        self,
        submission: ResultSubmission,
        binding: AssignmentBinding,
        *,
        task_id: str,
        inline_output: str | None = None,
        golden_expectation: GoldenExpectation | None = None,
    ) -> dict[str, Any]:
        signing_material = self.settings.jwt_signing_secret or "edgemint-development-signing-secret"
        attempt_key = binding.attempt_id
        existing = self.stored_results.setdefault(attempt_key, set())
        validate_submission_bindings(
            submission,
            binding,
            signing_material=signing_material,
            max_output_bytes=self.settings.file_max_upload_bytes,
            existing_result_digests=existing,
        )

        result_id = f"res_{uuid4().hex[:20]}"
        storage_ref = encrypted_storage_reference(workspace_id=binding.workspace_id, result_id=result_id)
        existing.add(submission.result_sha256)

        validation = validate_task_result(
            task_type=binding.task_type,
            inline_output=inline_output or submission.output_inline,
        )

        evidence = VerificationEvidence(
            task_type=binding.task_type,
            verification_level=binding.verification_level,
            result_sha256=submission.result_sha256,
            schema_valid=validation.schema_valid,
            artifact_checksum_valid=True,
            worker_signature_valid=True,
            business_rules_valid=validation.business_rules_valid,
            is_golden_task=binding.is_golden_task,
            policy_version=self.policy.path.name,
        )
        if golden_expectation is not None:
            golden = evaluate_golden_task(evidence, golden_expectation)
            if golden["status"] == "failed":
                decision = {
                    "outcome": "rejected",
                    "reason": golden["reason"],
                    "strategy": "golden",
                    "policyVersion": self.policy.path.name,
                    "deterministic": True,
                }
            else:
                decision = evaluate_automatic_verification(evidence, policy=self.policy)
        else:
            decision = evaluate_automatic_verification(evidence, policy=self.policy)

        verification_id = f"ver_{uuid4().hex[:20]}"
        evidence_id = f"vev_{uuid4().hex[:20]}"
        decision_record = record_decision_evidence(
            evidence_id=evidence_id,
            result_id=result_id,
            task_id=task_id,
            attempt_id=binding.attempt_id,
            assignment_id=binding.assignment_id,
            decision=decision,
            source_evidence={
                "resultSha256": submission.result_sha256,
                "taskType": binding.task_type,
                "verificationLevel": binding.verification_level,
                "metrics": submission.metrics,
            },
        )
        lineage = build_dispute_lineage(
            task_id=task_id,
            attempt_id=binding.attempt_id,
            assignment_id=binding.assignment_id,
            result_id=result_id,
            verification_id=verification_id,
            decision_evidence_id=evidence_id,
            result_sha256=submission.result_sha256,
            input_digest=binding.input_digest,
            model_digest=binding.model_digest,
        )
        review_item = None
        if decision["outcome"] in {"human_review", "escalate"}:
            review_item = self.human_review_queue.enqueue(
                task_id=task_id,
                result_id=result_id,
                reason=str(decision.get("reason", "verification_escalation")),
            )

        payload = {
            "resultId": result_id,
            "verificationId": verification_id,
            "storageRef": storage_ref,
            "decision": decision,
            "decisionEvidence": decision_record.to_dict(),
            "lineage": lineage,
            "humanReview": review_item.review_id if review_item else None,
        }
        self.decision_records.append(payload)
        return payload

    def run_consensus(
        self,
        *,
        task_type: str,
        verification_level: str,
        votes: list[ConsensusVote],
    ) -> dict[str, Any]:
        profile = self.policy.profile(task_type)
        consensus = profile["consensus"]
        decision = evaluate_consensus(
            votes,
            minimum_workers=int(consensus["minimumWorkers"]),
            minimum_similarity_milli=int(consensus["minimumSimilarityMilli"]),
        )
        decision["policyVersion"] = self.policy.path.name
        return decision

    def explain_decision(self, *, task_type: str) -> dict[str, Any]:
        profile = self.policy.profile(task_type)
        return {
            "taskType": task_type,
            "requiredSteps": profile["requiredSteps"],
            "outcomes": self.policy.outcomes,
            "maximumAutomaticRetries": self.policy.maximum_automatic_retries,
            "humanReviewQueue": self.human_review_queue.as_dict(),
            "evidenceRetentionDays": self.policy.evidence_retention_days,
        }
