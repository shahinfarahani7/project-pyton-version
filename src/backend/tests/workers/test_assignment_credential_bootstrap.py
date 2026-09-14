from __future__ import annotations

import base64
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch
from uuid import UUID, uuid4

import pytest

from edgemint.building_blocks.settings import Settings
from edgemint.security.lease_credentials import LeaseCredentialCipher
from edgemint.security.tokens import hash_session_token
from edgemint.workers.assignments import AssignmentCredentialBootstrapService
from edgemint.workers.errors import WorkerServiceError


class _MappingResult:
    def __init__(self, row: dict[str, object] | None) -> None:
        self._row = row

    def mappings(self) -> _MappingResult:
        return self

    def first(self) -> dict[str, object] | None:
        return self._row


def _settings(key: bytes) -> Settings:
    return Settings(
        environment="test",
        lease_credential_encryption_key=base64.urlsafe_b64encode(key).decode("ascii"),
        worker_api_public_base_url="https://worker.example.test",
    )


def test_lease_cipher_is_bound_to_target_device() -> None:
    cipher = LeaseCredentialCipher(key=b"k" * 32)
    device = uuid4()
    encrypted = cipher.encrypt("raw-lease-token", worker_device_id=device)

    assert cipher.decrypt(encrypted, worker_device_id=device) == "raw-lease-token"
    with pytest.raises(RuntimeError, match="LEASE_CREDENTIAL_DECRYPTION_FAILED"):
        cipher.decrypt(encrypted, worker_device_id=uuid4())
    assert b"raw-lease-token" not in encrypted


def test_production_requires_dedicated_lease_encryption_key() -> None:
    with pytest.raises(RuntimeError, match="LEASE_CREDENTIAL_ENCRYPTION_KEY_REQUIRED"):
        LeaseCredentialCipher.from_settings(Settings(environment="production"))


@pytest.mark.asyncio
async def test_bootstrap_returns_same_raw_credential_on_replay_without_rotation() -> None:
    key = b"e" * 32
    settings = _settings(key)
    device_id = uuid4()
    assignment_id = uuid4()
    lease_token = "lease-capability-secret"
    encrypted = LeaseCredentialCipher.from_settings(settings).encrypt(
        lease_token,
        worker_device_id=device_id,
    )
    now = datetime.now(UTC)
    row = {
        "assignment_id": assignment_id,
        "workspace_id": uuid4(),
        "fence_token": 9,
        "lease_token_hash": hash_session_token(lease_token),
        "lease_token_ciphertext": encrypted,
        "lease_expires_at_utc": now + timedelta(minutes=5),
        "start_deadline_at_utc": now + timedelta(minutes=1),
        "attempt_id": uuid4(),
        "revision_id": uuid4(),
        "task_public_id": "task_01JZ7M4J6QXW7YSF1DQ9Q32N5Z",
        "task_type": "document.ocr",
        "model_version_id": uuid4(),
    }
    connection = AsyncMock()
    connection.execute.side_effect = [_MappingResult(row), _MappingResult(row)]
    session = SimpleNamespace(
        device_id=device_id,
        device_status="active",
        attestation_status="verified",
        attestation_expires_at=now + timedelta(hours=1),
    )
    service = AssignmentCredentialBootstrapService(settings=settings)
    service.delivery_inbox.record_poll_delivery = AsyncMock(return_value=uuid4())
    service.execution_allocations.load_bootstrap_grant_for_attempt = AsyncMock(return_value=None)

    with patch(
        "edgemint.workers.assignments.resolve_worker_session",
        AsyncMock(return_value=session),
    ):
        first = await service.next_assignment(connection, access_token="worker-session")
        replay = await service.next_assignment(connection, access_token="worker-session")

    assert first is not None and replay is not None
    assert first["leaseToken"] == lease_token == replay["leaseToken"]
    assert first["fenceToken"] == 9
    assert first["executionStartsAutomatically"] is True
    assert first["assignmentMode"] == "auto"
    assert "accept" not in {key.lower() for key in first}
    assert "reject" not in {key.lower() for key in first}


@pytest.mark.asyncio
async def test_bootstrap_fails_closed_when_ciphertext_hash_does_not_match() -> None:
    key = b"h" * 32
    settings = _settings(key)
    device_id = uuid4()
    now = datetime.now(UTC)
    row = {
        "assignment_id": uuid4(),
        "fence_token": 1,
        "lease_token_hash": hash_session_token("different-token"),
        "lease_token_ciphertext": LeaseCredentialCipher.from_settings(settings).encrypt(
            "lease-token",
            worker_device_id=device_id,
        ),
        "lease_expires_at_utc": now + timedelta(minutes=5),
        "start_deadline_at_utc": now + timedelta(minutes=1),
        "attempt_id": uuid4(),
        "revision_id": uuid4(),
        "task_public_id": "task_01JZ7M4J6QXW7YSF1DQ9Q32N5Z",
        "task_type": "document.ocr",
        "model_version_id": UUID(int=1),
    }
    connection = AsyncMock()
    connection.execute.return_value = _MappingResult(row)
    session = SimpleNamespace(
        device_id=device_id,
        device_status="active",
        attestation_status="verified",
        attestation_expires_at=now + timedelta(hours=1),
    )

    with patch(
        "edgemint.workers.assignments.resolve_worker_session",
        AsyncMock(return_value=session),
    ), pytest.raises(WorkerServiceError) as exc:
        await AssignmentCredentialBootstrapService(settings=settings).next_assignment(
            connection,
            access_token="worker-session",
        )

    assert exc.value.code == "LEASE_CREDENTIAL_UNAVAILABLE"
