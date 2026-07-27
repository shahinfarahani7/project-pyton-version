from __future__ import annotations

import pytest
from edgemint.building_blocks.eventing.durable_websocket_client import DurableWebSocketClient, InFlightLimiter
from edgemint.building_blocks.eventing.relay import hash_resume_token, new_resume_token
from edgemint.building_blocks.eventing.transactional_outbox import OutboxEvent, cloud_event_payload_sha256


def test_in_flight_limiter_enforces_backpressure() -> None:
    limiter = InFlightLimiter(max_in_flight=2)
    limiter.reserve()
    limiter.reserve()
    with pytest.raises(RuntimeError, match="IN_FLIGHT_LIMIT_EXCEEDED"):
        limiter.reserve()
    limiter.release()
    assert limiter.can_accept()


def test_resume_token_hash_is_stable() -> None:
    token = "resume-token-value"  # noqa: S105
    assert hash_resume_token(token) == hash_resume_token(token)
    assert hash_resume_token(token) != hash_resume_token(token + "x")


def test_new_resume_token_rotates() -> None:
    token_a, hash_a, expiry_a = new_resume_token()
    token_b, hash_b, expiry_b = new_resume_token()
    assert token_a != token_b
    assert hash_a != hash_b
    assert expiry_b >= expiry_a


def test_durable_client_builds_resume_hello() -> None:
    client = DurableWebSocketClient(client_id="worker-1", client_version="1.0.0")
    client.remember_resume_token("resume-me")
    frame = client.build_hello_frame(request_id="req_TEST")
    assert frame["resumeToken"] == "resume-me"
    assert frame["type"] == "hello"


def test_cloud_event_payload_hash_is_deterministic() -> None:
    payload = {"specversion": "1.0", "id": "evt_1", "type": "task_created", "data": {"a": 1}}
    assert cloud_event_payload_sha256(payload) == cloud_event_payload_sha256(payload)


def test_outbox_event_dataclass_fields() -> None:
    event = OutboxEvent(
        event_type="task_created",
        aggregate_type="task",
        aggregate_id="task_1",
        aggregate_sequence=1,
        cloud_event={"id": "evt_1"},
    )
    assert event.aggregate_sequence == 1
