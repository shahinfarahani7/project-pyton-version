from __future__ import annotations

import base64
from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock
from uuid import uuid4

import pytest

from edgemint.building_blocks.settings import Settings
from edgemint.routing.service import RouterService
from edgemint.security.lease_credentials import LeaseCredentialCipher
from edgemint.security.tokens import hash_session_token


class _LeaseResult:
    def __init__(self, assignment_id: object) -> None:
        self._assignment_id = assignment_id

    def mappings(self) -> _LeaseResult:
        return self

    def first(self) -> dict[str, object]:
        return {
            "assignment_id": self._assignment_id,
            "fence_token": 4,
            "lease_expires_at_utc": datetime.now(UTC) + timedelta(minutes=5),
        }


class _InsertResult:
    pass


@pytest.mark.asyncio
async def test_router_persists_hash_and_encrypted_bootstrap_copy() -> None:
    key = b"r" * 32
    settings = Settings(
        environment="test",
        lease_credential_encryption_key=base64.urlsafe_b64encode(key).decode("ascii"),
        worker_resource_reservations_enabled=False,
    )
    connection = AsyncMock()
    assignment_id = uuid4()
    connection.execute.side_effect = [_LeaseResult(assignment_id), _InsertResult()]
    worker_device_id = uuid4()

    assignment = await RouterService(settings=settings).acquire_assignment_lease(
        connection,
        task_attempt_id=uuid4(),
        worker_id=uuid4(),
        worker_device_id=worker_device_id,
        router_instance_id="router-test",
    )

    first_params = connection.execute.await_args_list[0].args[1]
    second_params = connection.execute.await_args_list[1].args[1]
    assert second_params["assignment_id"] == assignment_id
    raw = assignment["leaseToken"]
    encrypted = second_params["lease_token_ciphertext"]
    assert first_params["lease_token_hash"] == hash_session_token(raw)
    assert raw.encode("utf-8") not in encrypted
    assert LeaseCredentialCipher.from_settings(settings).decrypt(
        encrypted,
        worker_device_id=worker_device_id,
    ) == raw
