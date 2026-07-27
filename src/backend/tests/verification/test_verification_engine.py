from __future__ import annotations

import base64
import hashlib
import hmac

import pytest
from edgemint.results.errors import ResultServiceError
from edgemint.results.intake import (
    AssignmentBinding,
    ResultSubmission,
    assert_exactly_one_output,
    validate_submission_bindings,
)
from edgemint.security.tokens import hash_session_token
from edgemint.verification.consensus import ConsensusVote, evaluate_consensus
from edgemint.verification.engine import (
    VerificationEvidence,
    compute_confidence_milli,
    evaluate_automatic_verification,
)
from edgemint.verification.errors import VerificationServiceError
from edgemint.verification.evidence import build_inputs_digest, record_decision_evidence
from edgemint.verification.golden import GoldenExpectation, evaluate_golden_task
from edgemint.verification.lineage import build_dispute_lineage
from edgemint.verification.policy import VerificationPolicy
from edgemint.verification.service import VerificationService


def sign_result(
    *,
    assignment_id: str,
    fence_token: int,
    result_sha256: str,
    output_artifact_id: str,
    signing_material: str = "edgemint-development-signing-secret",
) -> str:
    payload = f"{assignment_id}|{fence_token}|{result_sha256}|{output_artifact_id}"
    digest = hmac.new(signing_material.encode("utf-8"), payload.encode("utf-8"), hashlib.sha256).digest()
    return base64.b64encode(digest).decode("ascii")


def sample_submission(**overrides: object) -> ResultSubmission:
    base = {
        "assignment_id": "asg_test",
        "attempt_id": "att_test",
        "lease_token": "lease-token",
        "fence_token": 3,
        "result_sha256": "c" * 64,
        "output_artifact_id": "art_test",
        "signature": sign_result(
            assignment_id="asg_test",
            fence_token=3,
            result_sha256="c" * 64,
            output_artifact_id="art_test",
        ),
        "metrics": {"latencyMs": 1200},
        "output_inline": '{"content":"hello"}',
    }
    base.update(overrides)
    return ResultSubmission(**base)


def sample_binding(**overrides: object) -> AssignmentBinding:
    base = {
        "assignment_id": "asg_test",
        "attempt_id": "att_test",
        "workspace_id": "ws_test",
        "worker_id": "wrk_a",
        "worker_device_id": "dev_a",
        "task_type": "document.ocr",
        "verification_level": "standard",
        "lease_token_hash": hash_session_token("lease-token"),
        "fence_token": 3,
        "model_digest": "m" * 64,
        "input_digest": "i" * 64,
    }
    base.update(overrides)
    return AssignmentBinding(**base)


def test_exactly_one_output_required() -> None:
    with pytest.raises(ResultServiceError) as exc:
        assert_exactly_one_output(inline_output=None, output_file_id=None)
    assert exc.value.code == "RESULT_SCHEMA_INVALID"


def test_stale_fence_rejected() -> None:
    with pytest.raises(ResultServiceError) as exc:
        validate_submission_bindings(
            sample_submission(fence_token=2),
            sample_binding(fence_token=3),
            signing_material="edgemint-development-signing-secret",
            max_output_bytes=1024,
            existing_result_digests=set(),
        )
    assert exc.value.code == "ASSIGNMENT_STALE_FENCE"


def test_forged_signature_rejected() -> None:
    with pytest.raises(ResultServiceError) as exc:
        validate_submission_bindings(
            sample_submission(signature="invalid"),
            sample_binding(),
            signing_material="edgemint-development-signing-secret",
            max_output_bytes=1024,
            existing_result_digests=set(),
        )
    assert exc.value.code == "RESULT_SIGNATURE_INVALID"


def test_duplicate_result_rejected() -> None:
    digest = "d" * 64
    with pytest.raises(ResultServiceError) as exc:
        validate_submission_bindings(
            sample_submission(
                result_sha256=digest,
                signature=sign_result(
                    assignment_id="asg_test",
                    fence_token=3,
                    result_sha256=digest,
                    output_artifact_id="art_test",
                ),
            ),
            sample_binding(),
            signing_material="edgemint-development-signing-secret",
            max_output_bytes=1024,
            existing_result_digests={digest},
        )
    assert exc.value.code == "DUPLICATE_RESULT"


def test_model_and_input_digest_mismatch() -> None:
    with pytest.raises(ResultServiceError) as exc:
        validate_submission_bindings(
            sample_submission(submitted_model_digest="x" * 64),
            sample_binding(),
            signing_material="edgemint-development-signing-secret",
            max_output_bytes=1024,
            existing_result_digests=set(),
        )
    assert exc.value.code == "MODEL_DIGEST_MISMATCH"


def test_automatic_verification_is_deterministic() -> None:
    evidence = VerificationEvidence(
        task_type="document.ocr",
        verification_level="standard",
        result_sha256="c" * 64,
        schema_valid=True,
        artifact_checksum_valid=True,
        worker_signature_valid=True,
        business_rules_valid=True,
        is_golden_task=False,
        policy_version="default-v2.yaml",
    )
    first = evaluate_automatic_verification(evidence)
    second = evaluate_automatic_verification(evidence)
    assert first == second
    assert compute_confidence_milli(evidence) == first["confidenceMilli"]


def test_consensus_rejects_identity_collision() -> None:
    digest = "e" * 64
    votes = [
        ConsensusVote("wrk_a", "dev_a", digest, 950, "accept"),
        ConsensusVote("wrk_a", "dev_b", digest, 950, "accept"),
        ConsensusVote("wrk_c", "dev_c", digest, 950, "accept"),
    ]
    with pytest.raises(VerificationServiceError) as exc:
        evaluate_consensus(votes, minimum_workers=3, minimum_similarity_milli=910)
    assert exc.value.code == "CONSENSUS_IDENTITY_COLLISION"


def test_consensus_accepts_distinct_workers() -> None:
    digest = "f" * 64
    votes = [
        ConsensusVote("wrk_a", "dev_a", digest, 950, "accept"),
        ConsensusVote("wrk_b", "dev_b", digest, 950, "accept"),
        ConsensusVote("wrk_c", "dev_c", digest, 950, "accept"),
    ]
    decision = evaluate_consensus(votes, minimum_workers=3, minimum_similarity_milli=910)
    assert decision["outcome"] == "accepted"


def test_conflicting_consensus_results_fail() -> None:
    votes = [
        ConsensusVote("wrk_a", "dev_a", "a" * 64, 950, "accept"),
        ConsensusVote("wrk_b", "dev_b", "b" * 64, 950, "accept"),
        ConsensusVote("wrk_c", "dev_c", "b" * 64, 950, "accept"),
    ]
    with pytest.raises(VerificationServiceError) as exc:
        evaluate_consensus(votes, minimum_workers=3, minimum_similarity_milli=910)
    assert exc.value.code == "VERIFICATION_DISAGREEMENT"


def test_golden_task_mismatch_fails() -> None:
    evidence = VerificationEvidence(
        task_type="document.ocr",
        verification_level="standard",
        result_sha256="c" * 64,
        schema_valid=True,
        artifact_checksum_valid=True,
        worker_signature_valid=True,
        business_rules_valid=True,
        is_golden_task=True,
        policy_version="default-v2.yaml",
    )
    outcome = evaluate_golden_task(
        evidence,
        GoldenExpectation(task_type="document.ocr", expected_result_sha256="z" * 64),
    )
    assert outcome["status"] == "failed"


def test_verification_service_intake_and_lineage() -> None:
    service = VerificationService()
    body = service.intake_and_verify(
        sample_submission(),
        sample_binding(),
        task_id="tsk_test",
    )
    assert body["resultId"].startswith("res_")
    assert body["lineage"]["disputeReady"] is True
    assert body["decisionEvidence"]["immutable"] is True


def test_human_review_queue_on_escalation(monkeypatch: pytest.MonkeyPatch) -> None:
    service = VerificationService()

    def low_confidence(
        _: VerificationEvidence,
        *,
        policy: VerificationPolicy | None = None,
    ) -> dict[str, object]:
        return {
            "outcome": "human_review",
            "confidenceMilli": 850,
            "reason": "confidence_escalation",
            "policyVersion": "default-v2.yaml",
            "strategy": "automatic",
            "deterministic": True,
        }

    monkeypatch.setattr("edgemint.verification.service.evaluate_automatic_verification", low_confidence)
    body = service.intake_and_verify(sample_submission(), sample_binding(), task_id="tsk_review")
    assert body["humanReview"] is not None
    assert len(service.human_review_queue.pending()) == 1


def test_decision_evidence_digest_stable() -> None:
    source = {"resultSha256": "c" * 64, "taskType": "document.ocr"}
    assert build_inputs_digest(evidence=source) == build_inputs_digest(evidence=source)
    record = record_decision_evidence(
        evidence_id="vev_test",
        result_id="res_test",
        task_id="tsk_test",
        attempt_id="att_test",
        assignment_id="asg_test",
        decision={
            "outcome": "accepted",
            "strategy": "automatic",
            "policyVersion": "default-v2.yaml",
            "reason": "ok",
        },
        source_evidence=source,
    )
    assert record.inputs_digest == build_inputs_digest(evidence=source)


def test_dispute_lineage_contains_binding_nodes() -> None:
    lineage = build_dispute_lineage(
        task_id="tsk_test",
        attempt_id="att_test",
        assignment_id="asg_test",
        result_id="res_test",
        verification_id="ver_test",
        decision_evidence_id="vev_test",
        result_sha256="c" * 64,
        input_digest="i" * 64,
        model_digest="m" * 64,
    )
    kinds = [node["kind"] for node in lineage["chain"]]
    expected_kinds = [
        "task",
        "attempt",
        "assignment",
        "input",
        "model",
        "result",
        "verification",
        "decision_evidence",
    ]
    assert kinds == expected_kinds
