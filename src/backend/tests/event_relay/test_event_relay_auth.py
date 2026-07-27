from __future__ import annotations

from types import SimpleNamespace
from uuid import UUID

import pytest
from edgemint.building_blocks.settings import Settings
from edgemint.services import event_relay
from fastapi import HTTPException


def test_event_relay_service_auth_without_origin(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        event_relay,
        "settings",
        Settings(_env_file=None, environment="test", allow_insecure_development_tokens=True),
    )
    principal_id = UUID(int=5)
    websocket_service = SimpleNamespace(
        headers={
            "authorization": f"Bearer {principal_id}",
            "sec-websocket-protocol": "edgemint.events.v1",
        }
    )
    pid, workspace = event_relay._auth_context_from_headers(websocket_service)
    assert pid == principal_id
    assert workspace is None


def test_delegated_token_verifier_used_when_insecure_flag_disabled(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        event_relay,
        "settings",
        Settings(_env_file=None, environment="test", jwt_signing_secret="x" * 32),
    )
    websocket = SimpleNamespace(headers={"authorization": "Bearer not-a-uuid"})
    with pytest.raises(HTTPException):
        event_relay._auth_context_from_headers(websocket)
