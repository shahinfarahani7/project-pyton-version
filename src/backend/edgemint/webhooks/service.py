from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from secrets import token_hex
from typing import Any
from uuid import uuid4

from edgemint.webhooks.engine import evaluate_delivery
from edgemint.webhooks.errors import webhook_error
from edgemint.webhooks.policy import load_webhook_policy
from edgemint.webhooks.signature import sign_payload
from edgemint.webhooks.ssrf import validate_webhook_url


@dataclass(frozen=True, slots=True)
class DeliveryAttempt:
    attempt_number: int
    http_status: int | None
    recorded_at: str
    success: bool
    retry: bool
    base_delay_seconds: int
    scheduled_delay_seconds: int
    terminal: bool


@dataclass
class WebhookEndpoint:
    endpoint_id: str
    workspace_id: str
    owner_id: str
    url: str
    events: list[str]
    enabled: bool
    secret_current: str
    secret_previous: str | None = None
    secret_rotated_at: datetime | None = None


@dataclass
class WebhookDelivery:
    delivery_id: str
    domain_event_id: str
    endpoint_id: str
    event_type: str
    payload: dict[str, Any]
    status: str
    attempts: list[DeliveryAttempt] = field(default_factory=list)
    replay_of_delivery_id: str | None = None


@dataclass
class WebhookService:
    endpoints: dict[str, WebhookEndpoint] = field(default_factory=dict)
    deliveries: dict[str, WebhookDelivery] = field(default_factory=dict)
    dead_letter: list[str] = field(default_factory=list)
    processed_idempotency: set[str] = field(default_factory=set)
    seen_event_ids: set[str] = field(default_factory=set)
    metrics: dict[str, int] = field(
        default_factory=lambda: {
            "deliveriesEnqueued": 0,
            "deliveriesSucceeded": 0,
            "deliveriesFailed": 0,
            "deliveriesReplayed": 0,
            "deadLetterCount": 0,
        }
    )

    def create_endpoint(
        self,
        *,
        idempotency_key: str,
        workspace_id: str,
        owner_id: str,
        url: str,
        events: list[str],
    ) -> WebhookEndpoint:
        if idempotency_key in self.processed_idempotency:
            raise webhook_error("IDEMPOTENCY_CONFLICT")
        try:
            validate_webhook_url(url)
        except ValueError as exc:
            raise webhook_error("WEBHOOK_URL_FORBIDDEN", detail=str(exc)) from exc
        if not events:
            raise webhook_error("INPUT_SCHEMA_INVALID", detail="events required")
        endpoint = WebhookEndpoint(
            endpoint_id=f"whe_{uuid4().hex[:16]}",
            workspace_id=workspace_id,
            owner_id=owner_id,
            url=url,
            events=sorted(set(events)),
            enabled=True,
            secret_current=token_hex(32),
        )
        self.endpoints[endpoint.endpoint_id] = endpoint
        self.processed_idempotency.add(idempotency_key)
        return endpoint

    def rotate_secret(self, *, endpoint_id: str) -> WebhookEndpoint:
        endpoint = self._require_endpoint(endpoint_id)
        endpoint.secret_previous = endpoint.secret_current
        endpoint.secret_current = token_hex(32)
        endpoint.secret_rotated_at = datetime.now(UTC)
        return endpoint

    def disable_endpoint(self, *, endpoint_id: str) -> WebhookEndpoint:
        endpoint = self._require_endpoint(endpoint_id)
        endpoint.enabled = False
        return endpoint

    def active_secrets(self, endpoint: WebhookEndpoint) -> list[str]:
        policy = load_webhook_policy().spec
        overlap = timedelta(hours=int(policy["signature"]["secretOverlapHours"]))
        secrets = [endpoint.secret_current]
        if endpoint.secret_previous and endpoint.secret_rotated_at:
            if datetime.now(UTC) - endpoint.secret_rotated_at <= overlap:
                secrets.append(endpoint.secret_previous)
        return secrets

    def enqueue_delivery(
        self,
        *,
        endpoint_id: str,
        domain_event_id: str,
        event_type: str,
        payload: dict[str, Any],
    ) -> WebhookDelivery | None:
        endpoint = self._require_endpoint(endpoint_id)
        if not endpoint.enabled:
            return None
        if event_type not in endpoint.events:
            return None
        delivery = WebhookDelivery(
            delivery_id=f"whd_{uuid4().hex[:16]}",
            domain_event_id=domain_event_id,
            endpoint_id=endpoint_id,
            event_type=event_type,
            payload=payload,
            status="pending",
        )
        self.deliveries[delivery.delivery_id] = delivery
        self.metrics["deliveriesEnqueued"] += 1
        return delivery

    def build_signed_request(
        self,
        *,
        delivery: WebhookDelivery,
        timestamp: str | None = None,
    ) -> dict[str, str | bytes]:
        endpoint = self._require_endpoint(delivery.endpoint_id)
        ts = timestamp or str(int(datetime.now(UTC).timestamp()))
        raw_body = _canonical_json(delivery.payload).encode("utf-8")
        signature = sign_payload(secret=endpoint.secret_current, timestamp=ts, raw_body=raw_body)
        return {
            "url": endpoint.url,
            "timestamp": ts,
            "rawBody": raw_body,
            "headers": {
                "X-EdgeMint-Event-Id": delivery.domain_event_id,
                "X-EdgeMint-Timestamp": ts,
                "X-EdgeMint-Signature-v1": signature,
            },
        }

    def record_delivery_attempt(
        self,
        *,
        delivery_id: str,
        http_status: int,
        jitter_seed: int = 0,
    ) -> WebhookDelivery:
        delivery = self._require_delivery(delivery_id)
        attempt_number = len(delivery.attempts) + 1
        outcome = evaluate_delivery({"httpStatus": http_status, "attempt": attempt_number})
        base_delay = int(outcome["baseDelaySeconds"])
        scheduled_delay = apply_retry_jitter(base_delay, jitter_seed=jitter_seed)
        attempt = DeliveryAttempt(
            attempt_number=attempt_number,
            http_status=http_status,
            recorded_at=datetime.now(UTC).isoformat(),
            success=bool(outcome["success"]),
            retry=bool(outcome["retry"]),
            base_delay_seconds=base_delay,
            scheduled_delay_seconds=scheduled_delay,
            terminal=bool(outcome["terminal"]),
        )
        delivery.attempts.append(attempt)
        if outcome["success"]:
            delivery.status = "delivered"
            self.metrics["deliveriesSucceeded"] += 1
        elif outcome["terminal"]:
            delivery.status = "dead_letter"
            self.dead_letter.append(delivery_id)
            self.metrics["deliveriesFailed"] += 1
            self.metrics["deadLetterCount"] += 1
        else:
            delivery.status = "retry_scheduled"
        return delivery

    def replay_delivery(
        self,
        *,
        delivery_id: str,
        requester_id: str,
        authorized: bool,
    ) -> WebhookDelivery:
        if not authorized:
            raise webhook_error("REPLAY_NOT_AUTHORIZED")
        original = self._require_delivery(delivery_id)
        endpoint = self._require_endpoint(original.endpoint_id)
        if requester_id != endpoint.owner_id:
            raise webhook_error("REPLAY_NOT_AUTHORIZED")
        replay = WebhookDelivery(
            delivery_id=f"whd_{uuid4().hex[:16]}",
            domain_event_id=original.domain_event_id,
            endpoint_id=original.endpoint_id,
            event_type=original.event_type,
            payload=original.payload,
            status="pending",
            replay_of_delivery_id=original.delivery_id,
        )
        self.deliveries[replay.delivery_id] = replay
        self.metrics["deliveriesReplayed"] += 1
        self.metrics["deliveriesEnqueued"] += 1
        return replay

    def register_receiver_event(self, *, event_id: str) -> bool:
        if event_id in self.seen_event_ids:
            return False
        self.seen_event_ids.add(event_id)
        return True

    def delivery_metrics(self) -> dict[str, Any]:
        return {
            **self.metrics,
            "endpointCount": len(self.endpoints),
            "openDeliveries": sum(1 for item in self.deliveries.values() if item.status != "delivered"),
        }

    def _require_endpoint(self, endpoint_id: str) -> WebhookEndpoint:
        endpoint = self.endpoints.get(endpoint_id)
        if endpoint is None:
            raise webhook_error("TENANT_RESOURCE_NOT_FOUND", detail="endpoint not found")
        return endpoint

    def _require_delivery(self, delivery_id: str) -> WebhookDelivery:
        delivery = self.deliveries.get(delivery_id)
        if delivery is None:
            raise webhook_error("TENANT_RESOURCE_NOT_FOUND", detail="delivery not found")
        return delivery


def apply_retry_jitter(base_delay_seconds: int, *, jitter_seed: int) -> int:
    if base_delay_seconds <= 0:
        return 0
    policy = load_webhook_policy().spec
    jitter_bps = int(policy["retry"]["jitterBps"])
    max_extra = (base_delay_seconds * jitter_bps + 9999) // 10000
    if max_extra == 0:
        return base_delay_seconds
    extra = jitter_seed % (max_extra + 1)
    return base_delay_seconds + extra


def _canonical_json(payload: dict[str, Any]) -> str:
    import json

    return json.dumps(payload, separators=(",", ":"), sort_keys=True)
