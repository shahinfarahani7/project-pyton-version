from __future__ import annotations

from typing import Any

TEMPLATES: dict[str, str] = {
    "webhook.delivery.failed": (
        "Webhook delivery failed for endpoint {{endpointId}} "
        "(event {{eventType}}, delivery {{deliveryId}})."
    ),
    "webhook.secret.rotated": "Webhook secret rotated for endpoint {{endpointId}} at {{rotatedAt}}.",
    "webhook.endpoint.created": "Webhook endpoint {{endpointId}} created for workspace {{workspaceId}}.",
}


def render_template(template_id: str, context: dict[str, Any]) -> str:
    template = TEMPLATES.get(template_id)
    if template is None:
        raise KeyError(f"UNKNOWN_NOTIFICATION_TEMPLATE:{template_id}")
    rendered = template
    for key, value in context.items():
        rendered = rendered.replace(f"{{{{{key}}}}}", str(value))
    return rendered
