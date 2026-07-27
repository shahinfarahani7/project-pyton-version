from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
from dataclasses import dataclass
from typing import Any

from edgemint.results.errors import result_error
from edgemint.security.tokens import hash_session_token


@dataclass(frozen=True, slots=True)
class ResultSubmission:
    assignment_id: str
    attempt_id: str
    lease_token: str
    fence_token: int
    result_sha256: str
    output_artifact_id: str
    signature: str
    metrics: dict[str, Any]
    output_inline: str | None = None
    output_file_id: str | None = None
    submitted_model_digest: str | None = None
    submitted_input_digest: str | None = None


@dataclass(frozen=True, slots=True)
class AssignmentBinding:
    assignment_id: str
    attempt_id: str
    workspace_id: str
    worker_id: str
    worker_device_id: str
    task_type: str
    verification_level: str
    lease_token_hash: bytes
    fence_token: int
    model_digest: str
    input_digest: str
    is_golden_task: bool = False


def assert_exactly_one_output(*, inline_output: str | None, output_file_id: str | None) -> None:
    has_inline = inline_output is not None and inline_output != ""
    has_file = output_file_id is not None and output_file_id != ""
    if has_inline == has_file:
        raise result_error("RESULT_SCHEMA_INVALID", detail="exactly one output channel required")


def assert_output_size(*, inline_output: str | None, max_bytes: int) -> None:
    if inline_output is None:
        return
    encoded = inline_output.encode("utf-8")
    if len(encoded) > max_bytes:
        raise result_error("RESULT_OVERSIZED")


def assert_result_schema(*, inline_output: str | None, task_type: str) -> None:
    if inline_output is None:
        return
    try:
        payload = json.loads(inline_output)
    except json.JSONDecodeError as exc:
        raise result_error("RESULT_SCHEMA_INVALID", detail="inline output must be JSON") from exc
    if not isinstance(payload, dict):
        raise result_error("RESULT_SCHEMA_INVALID", detail="inline output must be an object")
    if task_type.startswith("document.") and "content" not in payload:
        raise result_error("RESULT_SCHEMA_INVALID", detail="document result requires content")


def verify_worker_signature(
    *,
    assignment_id: str,
    fence_token: int,
    result_sha256: str,
    output_artifact_id: str,
    signature: str,
    signing_material: str,
) -> None:
    payload = f"{assignment_id}|{fence_token}|{result_sha256}|{output_artifact_id}"
    digest = hmac.new(signing_material.encode("utf-8"), payload.encode("utf-8"), hashlib.sha256).digest()
    expected = base64.b64encode(digest).decode("ascii")
    if not secrets.compare_digest(signature, expected):
        raise result_error("RESULT_SIGNATURE_INVALID")


def validate_submission_bindings(
    submission: ResultSubmission,
    binding: AssignmentBinding,
    *,
    signing_material: str,
    max_output_bytes: int,
    existing_result_digests: set[str],
) -> None:
    if hash_session_token(submission.lease_token) != binding.lease_token_hash:
        raise result_error("LEASE_TOKEN_MISMATCH")
    if submission.fence_token != binding.fence_token:
        raise result_error("ASSIGNMENT_STALE_FENCE")
    if submission.submitted_model_digest and submission.submitted_model_digest != binding.model_digest:
        raise result_error("MODEL_DIGEST_MISMATCH")
    if submission.submitted_input_digest and submission.submitted_input_digest != binding.input_digest:
        raise result_error("INPUT_DIGEST_MISMATCH")
    assert_exactly_one_output(
        inline_output=submission.output_inline,
        output_file_id=submission.output_file_id,
    )
    assert_output_size(inline_output=submission.output_inline, max_bytes=max_output_bytes)
    assert_result_schema(inline_output=submission.output_inline, task_type=binding.task_type)
    verify_worker_signature(
        assignment_id=submission.assignment_id,
        fence_token=submission.fence_token,
        result_sha256=submission.result_sha256,
        output_artifact_id=submission.output_artifact_id,
        signature=submission.signature,
        signing_material=signing_material,
    )
    if submission.result_sha256 in existing_result_digests:
        raise result_error("DUPLICATE_RESULT")


def encrypted_storage_reference(*, workspace_id: str, result_id: str) -> str:
    return f"enc://{workspace_id}/results/{result_id}.blob"
