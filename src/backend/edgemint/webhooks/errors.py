from __future__ import annotations

from dataclasses import dataclass


@dataclass(slots=True)
class WebhookServiceError(Exception):
    code: str
    status: int
    title: str
    detail: str | None = None


def webhook_error(code: str, *, detail: str | None = None) -> WebhookServiceError:
    catalog: dict[str, tuple[int, str]] = {
        "AUTH_SCOPE_REQUIRED": (403, "Authorization scope required"),
        "IDEMPOTENCY_CONFLICT": (409, "Idempotency conflict"),
        "INPUT_SCHEMA_INVALID": (422, "Invalid request"),
        "REPLAY_NOT_AUTHORIZED": (403, "Replay not authorized"),
        "TENANT_RESOURCE_NOT_FOUND": (404, "Resource not found"),
        "WEBHOOK_URL_FORBIDDEN": (422, "Webhook URL forbidden"),
        "WEBHOOK_RETRY_EXHAUSTED": (409, "Webhook retry exhausted"),
    }
    status, title = catalog.get(code, (500, "Webhook operation failed"))
    return WebhookServiceError(code=code, status=status, title=title, detail=detail)
