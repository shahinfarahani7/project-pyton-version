from __future__ import annotations

from uuid import uuid4

from edgemint.workers.transport_recovery import (
    SubmissionClassification,
    TransportEventKind,
    aggregate_sequence_for_transport,
    classify_transport_submission,
    transport_event_identity,
    transport_payload_digest,
)


def test_transport_event_identity_bands_match_assignment_service() -> None:
    assignment_id = str(uuid4())
    fence = 11
    progress_identity = transport_event_identity(
        assignment_id=assignment_id,
        fence_token=fence,
        event_kind=TransportEventKind.PROGRESS,
        sequence=3,
    )
    assert progress_identity == f"progress:{assignment_id}:{fence}:3"
    assert aggregate_sequence_for_transport(
        fence_token=fence,
        event_kind=TransportEventKind.PROGRESS,
        sequence=3,
    ) == fence * 1_000_000_000 + 2_000_000 + 3
    assert aggregate_sequence_for_transport(
        fence_token=fence,
        event_kind=TransportEventKind.CHECKPOINT,
        sequence=2,
    ) == fence * 1_000_000_000 + 3_000_000 + 2


def test_classify_transport_vs_task_retry() -> None:
    assert (
        classify_transport_submission(is_new=True, conflict=False)
        == SubmissionClassification.TRANSPORT_FRESH
    )
    assert (
        classify_transport_submission(is_new=False, conflict=False)
        == SubmissionClassification.TRANSPORT_REPLAY
    )
    assert (
        classify_transport_submission(is_new=False, conflict=True)
        == SubmissionClassification.TRANSPORT_CONFLICT
    )
    assert (
        classify_transport_submission(
            is_new=True,
            conflict=False,
            unauthorized_task_retry=True,
        )
        == SubmissionClassification.TASK_RETRY_UNAUTHORIZED
    )


def test_transport_payload_digest_is_order_independent() -> None:
    first = transport_payload_digest({"sequence": 1, "stage": "llm-map", "progressBps": 4000})
    second = transport_payload_digest({"progressBps": 4000, "stage": "llm-map", "sequence": 1})
    assert first == second


def test_worker_policy_documents_forbidden_scheduler() -> None:
    from pathlib import Path

    policy = (
        Path(__file__).resolve().parents[4]
        / "dsl/policies/worker/transport-recovery-boundary-v1.yaml"
    ).read_text(encoding="utf-8")
    for token in (
        "LocalTaskSelector",
        "mustNotRerunInferenceOnLostAck: true",
        "deliveryAckMeaning: transport_receipt_only",
        "stageRetryRequiresSeparateServerAuthorization: true",
    ):
        assert token in policy
