from __future__ import annotations

from uuid import UUID


DEFAULT_ENTITLEMENT_COMPONENT = "completion"


def entitlement_business_key(
    *,
    workspace_id: UUID,
    task_run_id: UUID,
    component_id: str = DEFAULT_ENTITLEMENT_COMPONENT,
) -> str:
    return f"ent:{workspace_id}:{task_run_id}:{component_id}"


def external_effect_key(
    *,
    destination_type: str,
    destination_id: str,
    idempotency_key: str,
) -> str:
    return f"{destination_type}|{destination_id}|{idempotency_key}"


def evaluate_payload_idempotency(
    *,
    existing_digest: str | None,
    incoming_digest: str,
) -> str:
    """Return replay | conflict | fresh."""
    if existing_digest is None:
        return "fresh"
    if existing_digest == incoming_digest:
        return "replay"
    return "conflict"
