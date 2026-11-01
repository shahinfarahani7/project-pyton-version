from __future__ import annotations

import json
from datetime import UTC, datetime, timedelta
from uuid import UUID

import pytest
from edgemint.security.api_key_directory import ApiKeyDirectory, ApiKeyError


def _create(keys: ApiKeyDirectory, **overrides: object) -> dict[str, object]:
    payload: dict[str, object] = {
        "workspace_id": UUID(int=7),
        "principal_id": UUID(int=8),
        "name": "Partner integration",
        "scopes": ["customer.tasks:write", "customer.tasks:read"],
        "expires_at": None,
        "allowed_cidrs": [],
        "idempotency_key": "idem-create-partner-01",
    }
    payload.update(overrides)
    return keys.create(**payload)  # type: ignore[arg-type]


def test_api_key_is_scoped_idempotent_and_rotatable() -> None:
    keys = ApiKeyDirectory()
    workspace_id = UUID(int=7)
    created = _create(keys)
    secret = str(created["secret"])
    assert secret.startswith("emk_")
    assert created["prefix"] == secret[:11]
    assert created["scopes"] == ["customer.tasks:read", "customer.tasks:write"]
    assert "secret" not in keys.list_public(workspace_id)["items"][0]

    replay = _create(keys)
    assert replay["secret"] == secret
    assert len(keys.list_public(workspace_id)["items"]) == 1

    with pytest.raises(ApiKeyError, match="IDEMPOTENCY_CONFLICT") as conflict:
        _create(keys, name="Different integration")
    assert conflict.value.status == 409

    with pytest.raises(ApiKeyError, match="API_KEY_SCOPE_FORBIDDEN"):
        _create(
            keys,
            name="Billing key",
            scopes=["customer.billing:read"],
            idempotency_key="idem-create-billing-01",
        )

    serialized_audit = json.dumps(keys.audits_for(workspace_id))
    serialized_events = json.dumps(keys.events_for(workspace_id))
    assert secret not in serialized_audit
    assert secret not in serialized_events
    assert keys.events_for(workspace_id)[0]["type"] == "api_key.created"

    with pytest.raises(ApiKeyError, match="API_KEY_NAME_CONFLICT"):
        _create(keys, idempotency_key="idem-create-partner-02")

    rotated = keys.rotate(
        workspace_id=workspace_id,
        principal_id=UUID(int=8),
        key_id=str(created["id"]),
        idempotency_key="idem-rotate-partner-01",
    )
    assert rotated["secret"] != secret
    assert keys.authenticate(secret, client_ip=None) is None
    current = keys.authenticate(str(rotated["secret"]), client_ip=None)
    assert current is not None
    assert current.key_id == created["id"]
    assert keys.events_for(workspace_id)[-1]["type"] == "api_key.rotated"

    network = _create(
        keys,
        name="Office network",
        scopes=["customer.tasks:read"],
        allowed_cidrs=["10.0.0.0/8"],
        idempotency_key="idem-create-office-01",
    )
    denied = keys.authenticate(str(network["secret"]), client_ip="192.0.2.10")
    assert denied is not None
    assert denied.denied_code == "API_KEY_IP_DENIED"
    allowed = keys.authenticate(str(network["secret"]), client_ip="10.1.2.3")
    assert allowed is not None
    assert allowed.denied_code is None
    assert allowed.scopes == ("customer.tasks:read",)

    record = next(item for item in keys._keys if item.public_id == network["id"])
    record.expires_at = datetime.now(tz=UTC) - timedelta(seconds=1)
    assert keys.authenticate(str(network["secret"]), client_ip="10.1.2.3") is None

    revoked = keys.revoke(
        workspace_id=workspace_id,
        principal_id=UUID(int=8),
        key_id=str(created["id"]),
        idempotency_key="idem-revoke-partner-01",
    )
    assert revoked["status"] == "revoked"
    assert keys.authenticate(str(rotated["secret"]), client_ip=None) is None
    replacement = _create(keys, idempotency_key="idem-create-partner-03")
    assert replacement["id"] != created["id"]
