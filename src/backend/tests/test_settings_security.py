from types import SimpleNamespace
from uuid import UUID

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from edgemint.building_blocks.settings import Settings
from edgemint.services import event_relay


def test_database_url_is_required_at_use_time() -> None:
    settings = Settings(_env_file=None)
    assert settings.database_url is None
    with pytest.raises(RuntimeError, match="EDGEMINT_DATABASE_URL_REQUIRED"):
        settings.require_database_url()


def test_insecure_tokens_are_forbidden_in_production() -> None:
    with pytest.raises(ValidationError, match="INSECURE_DEVELOPMENT_TOKENS_FORBIDDEN"):
        Settings(
            _env_file=None,
            environment="production",
            allow_insecure_development_tokens=True,
        )


def test_raw_uuid_bearer_is_rejected_by_default(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(event_relay, "settings", Settings(_env_file=None))
    websocket = SimpleNamespace(headers={"authorization": f"Bearer {UUID(int=1)}"})
    with pytest.raises(HTTPException) as exc:
        event_relay._auth_context_from_headers(websocket)
    assert exc.value.status_code == 401


def test_raw_uuid_bearer_requires_explicit_development_flag(monkeypatch: pytest.MonkeyPatch) -> None:
    expected = UUID(int=2)
    monkeypatch.setattr(
        event_relay,
        "settings",
        Settings(
            _env_file=None,
            environment="development",
            allow_insecure_development_tokens=True,
        ),
    )
    websocket = SimpleNamespace(headers={"authorization": f"Bearer {expected}"})
    principal_id, _workspace = event_relay._auth_context_from_headers(websocket)
    assert principal_id == expected
