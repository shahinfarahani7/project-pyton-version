from __future__ import annotations

import base64
import hashlib
import hmac
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src" / "backend"))

from edgemint.results.errors import ResultServiceError  # noqa: E402
from edgemint.results.intake import AssignmentBinding, ResultSubmission  # noqa: E402
from edgemint.security.tokens import hash_session_token  # noqa: E402
from edgemint.verification.consensus import ConsensusVote, evaluate_consensus  # noqa: E402
from edgemint.verification.engine import VerificationEvidence, evaluate_automatic_verification  # noqa: E402
from edgemint.verification.policy import VerificationPolicy  # noqa: E402
from edgemint.verification.service import VerificationService  # noqa: E402


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


def sample_submission() -> ResultSubmission:
    result_sha256 = "c" * 64
    return ResultSubmission(
        assignment_id="asg_test",
        attempt_id="att_test",
        lease_token="lease-token",
        fence_token=3,
        result_sha256=result_sha256,
        output_artifact_id="art_test",
        signature=sign_result(
            assignment_id="asg_test",
            fence_token=3,
            result_sha256=result_sha256,
            output_artifact_id="art_test",
        ),
        metrics={"latencyMs": 1200},
        output_inline='{"content":"hello"}',
    )


def sample_binding() -> AssignmentBinding:
    return AssignmentBinding(
        assignment_id="asg_test",
        attempt_id="att_test",
        workspace_id="ws_test",
        worker_id="wrk_a",
        worker_device_id="dev_a",
        task_type="document.ocr",
        verification_level="standard",
        lease_token_hash=hash_session_token("lease-token"),
        fence_token=3,
        model_digest="m" * 64,
        input_digest="i" * 64,
    )


def contract_checks() -> list[str]:
    errors: list[str] = []
    result_src = (ROOT / "src/backend/edgemint/services/result.py").read_text(encoding="utf-8")
    verification_src = (ROOT / "src/backend/edgemint/services/verification.py").read_text(encoding="utf-8")
    service_src = (ROOT / "src/backend/edgemint/verification/service.py").read_text(encoding="utf-8")
    for token in [
        "validate_submission_bindings",
        "evaluate_automatic_verification",
        "evaluate_consensus",
        "record_decision_evidence",
        "build_dispute_lineage",
        "HumanReviewQueue",
    ]:
        if token not in service_src:
            errors.append(f"verification service missing:{token}")
    if '"/internal/result/intake"' not in result_src:
        errors.append("result api missing intake route")
    if '"/internal/verification/consensus"' not in verification_src:
        errors.append("verification api missing consensus route")
    if '"/verification/policy"' not in verification_src:
        errors.append("verification api missing policy route")
    policy = VerificationPolicy.load()
    if "accepted" not in policy.outcomes:
        errors.append("verification policy missing accepted outcome")
    return errors


def semantic_checks() -> list[str]:
    errors: list[str] = []
    service = VerificationService()
    submission = sample_submission()
    binding = sample_binding()
    accepted = service.intake_and_verify(submission, binding, task_id="tsk_e2e")
    if accepted["decision"]["outcome"] not in {"accepted", "accepted_with_warning", "consensus", "human_review"}:
        errors.append("unexpected automatic outcome")

    try:
        service.intake_and_verify(submission, binding, task_id="tsk_e2e")
        errors.append("duplicate result should fail")
    except ResultServiceError as exc:
        if exc.code != "DUPLICATE_RESULT":
            errors.append("duplicate result raised unexpected error")
    except Exception:
        errors.append("duplicate result raised unexpected error")

    forged = sample_submission()
    forged = ResultSubmission(
        assignment_id=forged.assignment_id,
        attempt_id=forged.attempt_id,
        lease_token=forged.lease_token,
        fence_token=forged.fence_token,
        result_sha256=forged.result_sha256,
        output_artifact_id=forged.output_artifact_id,
        signature="forged",
        metrics=forged.metrics,
        output_inline=forged.output_inline,
    )
    try:
        service.intake_and_verify(forged, binding, task_id="tsk_e2e_forged")
        errors.append("forged signature should fail")
    except ResultServiceError as exc:
        if exc.code != "RESULT_SIGNATURE_INVALID":
            errors.append("forged signature raised unexpected error")
    except Exception:
        errors.append("forged signature raised unexpected error")

    digest = "a" * 64
    votes = [
        ConsensusVote("wrk_1", "dev_1", digest, 950, "accept"),
        ConsensusVote("wrk_2", "dev_2", digest, 950, "accept"),
        ConsensusVote("wrk_3", "dev_3", digest, 950, "accept"),
    ]
    consensus = evaluate_consensus(votes, minimum_workers=3, minimum_similarity_milli=910)
    if consensus["outcome"] != "accepted":
        errors.append("consensus quorum should accept")

    evidence = VerificationEvidence(
        task_type="document.ocr",
        verification_level="standard",
        result_sha256=digest,
        schema_valid=True,
        artifact_checksum_valid=True,
        worker_signature_valid=True,
        business_rules_valid=True,
        is_golden_task=False,
        policy_version="default-v2.yaml",
    )
    first = evaluate_automatic_verification(evidence)
    second = evaluate_automatic_verification(evidence)
    if first != second:
        errors.append("verification decisions must be deterministic")

    return errors


def main() -> int:
    errors = contract_checks() + semantic_checks()
    if errors:
        for item in errors:
            print(item)
        return 1
    print("result verification e2e checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
