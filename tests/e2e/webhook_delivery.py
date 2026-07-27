from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src" / "backend"))

from edgemint.notifications.templates import render_template  # noqa: E402
from edgemint.webhooks.engine import evaluate_delivery  # noqa: E402
from edgemint.webhooks.errors import WebhookServiceError  # noqa: E402
from edgemint.webhooks.service import WebhookService  # noqa: E402
from edgemint.webhooks.signature import sign_payload, verify_signature  # noqa: E402


def contract_checks() -> list[str]:
    errors: list[str] = []
    webhook_src = (ROOT / "src/backend/edgemint/services/webhook.py").read_text(encoding="utf-8")
    notification_src = (ROOT / "src/backend/edgemint/services/notification.py").read_text(encoding="utf-8")
    for route in [
        '"/internal/webhook/endpoints"',
        '"/internal/webhook/deliveries:enqueue"',
        '"/internal/webhook/deliveries:record-attempt"',
        '"/internal/webhook/deliveries:replay"',
        '"/internal/webhook/metrics"',
        '"/internal/webhook/dead-letter"',
    ]:
        if route not in webhook_src:
            errors.append(f"webhook api missing route {route}")
    if '"/internal/notifications/templates:render"' not in notification_src:
        errors.append("notification api missing render route")
    return errors


def semantic_checks() -> list[str]:
    errors: list[str] = []
    outcome = evaluate_delivery({"httpStatus": 429, "attempt": 4})
    if not outcome["retry"] or outcome["baseDelaySeconds"] != 600:
        errors.append("retry policy mismatch for 429 attempt 4")

    service = WebhookService()
    endpoint = service.create_endpoint(
        idempotency_key="idem-e2e",
        workspace_id="ws_e2e",
        owner_id="owner_e2e",
        url="https://example.com/webhooks",
        events=["task.completed"],
    )
    delivery = service.enqueue_delivery(
        endpoint_id=endpoint.endpoint_id,
        domain_event_id="evt_e2e",
        event_type="task.completed",
        payload={"specversion": "1.0", "id": "evt_e2e", "type": "task.completed"},
    )
    if delivery is None:
        errors.append("delivery should be accepted for subscribed event")
    assert delivery is not None
    signed = service.build_signed_request(delivery=delivery, timestamp="1700000000")
    signature = signed["headers"]["X-EdgeMint-Signature-v1"]
    if not verify_signature(
        secrets=service.active_secrets(endpoint),
        timestamp="1700000000",
        raw_body=signed["rawBody"],
        signature=signature,
        tolerance_seconds=300,
        now_epoch=1700000100,
    ):
        errors.append("signed payload verification failed")

    service.record_delivery_attempt(delivery_id=delivery.delivery_id, http_status=200)
    if delivery.status != "delivered":
        errors.append("successful attempt should mark delivery delivered")

    failed = service.enqueue_delivery(
        endpoint_id=endpoint.endpoint_id,
        domain_event_id="evt_fail",
        event_type="task.completed",
        payload={"id": "evt_fail"},
    )
    assert failed is not None
    for _ in range(8):
        service.record_delivery_attempt(delivery_id=failed.delivery_id, http_status=500)
    if failed.delivery_id not in service.dead_letter:
        errors.append("exhausted retries should land in dead letter")

    replay = service.replay_delivery(
        delivery_id=failed.delivery_id,
        requester_id="owner_e2e",
        authorized=True,
    )
    if replay.domain_event_id != "evt_fail":
        errors.append("replay must preserve domain event id")
    if replay.delivery_id == failed.delivery_id:
        errors.append("replay must create a new delivery id")

    try:
        service.create_endpoint(
            idempotency_key="idem-e2e",
            workspace_id="ws_e2e",
            owner_id="owner_e2e",
            url="https://example.com/webhooks",
            events=["task.completed"],
        )
        errors.append("duplicate idempotency should fail")
    except WebhookServiceError as exc:
        if exc.code != "IDEMPOTENCY_CONFLICT":
            errors.append("duplicate idempotency unexpected error")

    try:
        service.create_endpoint(
            idempotency_key="idem-private",
            workspace_id="ws_e2e",
            owner_id="owner_e2e",
            url="https://192.168.0.10/hook",
            events=["task.completed"],
        )
        errors.append("private webhook url should be rejected")
    except WebhookServiceError as exc:
        if exc.code != "WEBHOOK_URL_FORBIDDEN":
            errors.append("private webhook url unexpected error")

    body = render_template(
        "webhook.delivery.failed",
        {"endpointId": endpoint.endpoint_id, "eventType": "task.completed", "deliveryId": failed.delivery_id},
    )
    if endpoint.endpoint_id not in body:
        errors.append("notification template render failed")

    metrics = service.delivery_metrics()
    if metrics["deliveriesEnqueued"] < 3:
        errors.append("delivery metrics under-counted")
    return errors


def main() -> int:
    errors = contract_checks() + semantic_checks()
    if errors:
        for item in errors:
            print(item)
        return 1
    print("webhook delivery e2e checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
