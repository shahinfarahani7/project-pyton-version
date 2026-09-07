"""T21 audit scenarios: bounded decode and privacy cleanup (P8-A21 / A21)."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from edgemint.files.artifact_privacy import (
    UploadArtifactState,
    cross_task_isolation_violated,
    evaluate_retention_cleanup,
    evaluate_upload_acceptance,
)
from edgemint.files.input_decode_bounds import (
    DecodeFailureReason,
    evaluate_decode_admission,
    estimate_decoded_bytes,
    load_input_decode_privacy_policy,
)


def test_t21_policy_declares_decode_bounds_and_privacy_rules() -> None:
    policy = load_input_decode_privacy_policy()
    assert policy["decodeBounds"]["maxDecodedBytes"] == 536870912
    assert policy["uploadArtifacts"]["acceptOnlyCompleteUploads"] is True
    assert policy["privacyCleanup"]["crossTaskLeakageForbidden"] is True


def test_t21_huge_pdf_decode_rejected_before_admission() -> None:
    decision = evaluate_decode_admission(
        content_type="application/pdf",
        compressed_bytes=20_000_000,
        page_count=600,
    )
    assert decision.permitted is False
    assert decision.reason_code == DecodeFailureReason.DECODE_BOUNDS_EXCEEDED


def test_t21_huge_image_pixels_rejected() -> None:
    decision = evaluate_decode_admission(
        content_type="image/png",
        compressed_bytes=2_000_000,
        image_width=10000,
        image_height=10000,
    )
    assert decision.permitted is False
    assert decision.reason_code == DecodeFailureReason.DECODE_BOUNDS_EXCEEDED


def test_t21_reasonable_input_admitted_with_decoded_estimate() -> None:
    estimated = estimate_decoded_bytes(
        content_type="image/jpeg",
        compressed_bytes=1_000_000,
        image_width=1024,
        image_height=768,
    )
    decision = evaluate_decode_admission(
        content_type="image/jpeg",
        compressed_bytes=1_000_000,
        image_width=1024,
        image_height=768,
    )
    assert estimated == 1024 * 768 * 4
    assert decision.permitted is True


def test_t21_partial_upload_not_accepted_as_artifact() -> None:
    decision = evaluate_upload_acceptance(
        upload_state=UploadArtifactState.PARTIAL,
        sha256_verified=False,
        size_matches=False,
    )
    assert decision.accepted is False
    assert decision.reason_code == "UPLOAD_INCOMPLETE"


def test_t21_retention_blocks_cleanup_until_window_elapses() -> None:
    now = datetime(2026, 9, 6, tzinfo=UTC)
    created = now - timedelta(minutes=10)
    blocked = evaluate_retention_cleanup(
        created_at=created,
        now=now,
        retention_minutes=60,
        has_active_references=False,
    )
    assert blocked.permitted is False

    allowed = evaluate_retention_cleanup(
        created_at=now - timedelta(minutes=90),
        now=now,
        retention_minutes=60,
        has_active_references=False,
    )
    assert allowed.permitted is True


def test_t21_active_checkpoint_reference_blocks_cleanup() -> None:
    now = datetime(2026, 9, 6, tzinfo=UTC)
    decision = evaluate_retention_cleanup(
        created_at=now - timedelta(hours=2),
        now=now,
        retention_minutes=60,
        has_active_references=True,
    )
    assert decision.permitted is False


def test_t21_cross_task_buffer_isolation_detected() -> None:
    assert cross_task_isolation_violated(
        prior_assignment_id="asg_a",
        next_assignment_id="asg_b",
        shared_buffer_owner="asg_a",
    )
    assert not cross_task_isolation_violated(
        prior_assignment_id="asg_a",
        next_assignment_id="asg_b",
        shared_buffer_owner=None,
    )
