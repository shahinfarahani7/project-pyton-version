from __future__ import annotations

import json
from pathlib import Path

import pytest
from edgemint.webhooks.engine import evaluate_delivery
from edgemint.webhooks.errors import WebhookServiceError
from edgemint.webhooks.service import WebhookService, apply_retry_jitter
from edgemint.webhooks.signature import sign_payload, verify_signature
from edgemint.webhooks.ssrf import validate_webhook_url

VECTOR_PATH = Path(__file__).resolve().parents[4] / "tests" / "vectors" / "webhook-vectors.jsonl"


@pytest.mark.parametrize(
    ("http_status", "attempt", "expected"),
    [
        (200, 1, {"success": True, "retry": False, "baseDelaySeconds": 0, "terminal": False}),
        (500, 1, {"success": False, "retry": True, "baseDelaySeconds": 10, "terminal": False}),
        (400, 4, {"success": False, "retry": False, "baseDelaySeconds": 0, "terminal": True}),
        (504, 8, {"success": False, "retry": False, "baseDelaySeconds": 0, "terminal": True}),
    ],
)
def test_evaluate_delivery_samples(http_status: int, attempt: int, expected: dict) -> None:
    assert evaluate_delivery({"httpStatus": http_status, "attempt": attempt}) == expected


def test_evaluate_delivery_matches_vector_file_sample() -> None:
    with VECTOR_PATH.open(encoding="utf-8") as handle:
        for line in handle:
            case = json.loads(line)
            assert evaluate_delivery(case["input"]) == case["expected"]


def test_signature_round_trip_and_rotation_overlap() -> None:
    signing_key = "test-signing-key"
    body = b'{"id":"evt_1"}'
    timestamp = "1700000000"
    signature = sign_payload(secret=signing_key, timestamp=timestamp, raw_body=body)
    assert verify_signature(
        secrets=[signing_key],
        timestamp=timestamp,
        raw_body=body,
        signature=signature,
        tolerance_seconds=300,
        now_epoch=1700000100,
    )
    assert not verify_signature(
        secrets=[signing_key],
        timestamp=timestamp,
        raw_body=body,
        signature=signature,
        tolerance_seconds=300,
        now_epoch=1700000400,
    )


def test_ssrf_blocks_private_and_local_targets() -> None:
    validate_webhook_url("https://example.com/hook")
    with pytest.raises(ValueError, match="PRIVATE_ADDRESS"):
        validate_webhook_url("https://127.0.0.1/hook")
    with pytest.raises(ValueError, match="HOST_FORBIDDEN"):
        validate_webhook_url("https://localhost/hook")
    with pytest.raises(ValueError, match="SCHEME_FORBIDDEN"):
        validate_webhook_url("http://example.com/hook")


def test_create_endpoint_rejects_private_url() -> None:
    service = WebhookService()
    with pytest.raises(WebhookServiceError) as exc:
        service.create_endpoint(
            idempotency_key="idem-1",
            workspace_id="ws_1",
            owner_id="usr_1",
            url="https://10.0.0.1/hook",
            events=["task.completed"],
        )
    assert exc.value.code == "WEBHOOK_URL_FORBIDDEN"


def test_event_filter_and_replay_preserves_domain_event() -> None:
    service = WebhookService()
    endpoint = service.create_endpoint(
        idempotency_key="idem-ep",
        workspace_id="ws_1",
        owner_id="owner_1",
        url="https://example.com/hook",
        events=["task.completed"],
    )
    skipped = service.enqueue_delivery(
        endpoint_id=endpoint.endpoint_id,
        domain_event_id="evt_domain",
        event_type="task.failed",
        payload={"taskId": "tsk_1"},
    )
    assert skipped is None
    delivery = service.enqueue_delivery(
        endpoint_id=endpoint.endpoint_id,
        domain_event_id="evt_domain",
        event_type="task.completed",
        payload={"taskId": "tsk_1"},
    )
    assert delivery is not None
    service.record_delivery_attempt(delivery_id=delivery.delivery_id, http_status=500)
    replay = service.replay_delivery(
        delivery_id=delivery.delivery_id,
        requester_id="owner_1",
        authorized=True,
    )
    assert replay.delivery_id != delivery.delivery_id
    assert replay.domain_event_id == "evt_domain"
    assert replay.replay_of_delivery_id == delivery.delivery_id


def test_replay_requires_authorization() -> None:
    service = WebhookService()
    endpoint = service.create_endpoint(
        idempotency_key="idem-ep2",
        workspace_id="ws_1",
        owner_id="owner_1",
        url="https://example.com/hook",
        events=["task.completed"],
    )
    delivery = service.enqueue_delivery(
        endpoint_id=endpoint.endpoint_id,
        domain_event_id="evt_2",
        event_type="task.completed",
        payload={"taskId": "tsk_2"},
    )
    assert delivery is not None
    with pytest.raises(WebhookServiceError) as exc:
        service.replay_delivery(
            delivery_id=delivery.delivery_id,
            requester_id="intruder",
            authorized=True,
        )
    assert exc.value.code == "REPLAY_NOT_AUTHORIZED"


def test_terminal_failure_moves_to_dead_letter() -> None:
    service = WebhookService()
    endpoint = service.create_endpoint(
        idempotency_key="idem-ep3",
        workspace_id="ws_1",
        owner_id="owner_1",
        url="https://example.com/hook",
        events=["task.completed"],
    )
    delivery = service.enqueue_delivery(
        endpoint_id=endpoint.endpoint_id,
        domain_event_id="evt_3",
        event_type="task.completed",
        payload={"taskId": "tsk_3"},
    )
    assert delivery is not None
    for _ in range(8):
        service.record_delivery_attempt(delivery_id=delivery.delivery_id, http_status=500)
    assert delivery.status == "dead_letter"
    assert delivery.delivery_id in service.dead_letter


def test_retry_jitter_is_bounded() -> None:
    base = 600
    policy_max = (base * 2000 + 9999) // 10000
    for seed in range(20):
        value = apply_retry_jitter(base, jitter_seed=seed)
        assert base <= value <= base + policy_max


def test_receiver_event_deduplication() -> None:
    service = WebhookService()
    assert service.register_receiver_event(event_id="evt_dup") is True
    assert service.register_receiver_event(event_id="evt_dup") is False
