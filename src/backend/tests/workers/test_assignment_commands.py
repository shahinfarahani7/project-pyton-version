from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from edgemint.security.tokens import hash_session_token
from edgemint.workers.assignments import AssignmentCommandService
from edgemint.workers.errors import WorkerServiceError


def _active_row(*, token: str = "lease-token", fence: int = 7) -> dict[str, object]:
    return {
        "fence_token": fence,
        "lease_token_hash": hash_session_token(token),
        "lease_expires_at_utc": datetime.now(UTC) + timedelta(minutes=2),
    }


def test_active_lease_credential_is_accepted() -> None:
    AssignmentCommandService._verify_active_credential(
        _active_row(),
        lease_token="lease-token",
        fence_token=7,
    )


def test_stale_fence_is_rejected_before_state_change() -> None:
    with pytest.raises(WorkerServiceError) as exc:
        AssignmentCommandService._verify_active_credential(
            _active_row(fence=8),
            lease_token="lease-token",
            fence_token=7,
        )
    assert exc.value.code == "ASSIGNMENT_STALE_FENCE"


def test_wrong_lease_token_is_rejected_before_state_change() -> None:
    with pytest.raises(WorkerServiceError) as exc:
        AssignmentCommandService._verify_active_credential(
            _active_row(),
            lease_token="wrong-token",
            fence_token=7,
        )
    assert exc.value.code == "LEASE_TOKEN_MISMATCH"


def test_expired_lease_is_rejected_before_state_change() -> None:
    row = _active_row()
    row["lease_expires_at_utc"] = datetime.now(UTC) - timedelta(seconds=1)
    with pytest.raises(WorkerServiceError) as exc:
        AssignmentCommandService._verify_active_credential(
            row,
            lease_token="lease-token",
            fence_token=7,
        )
    assert exc.value.code == "ASSIGNMENT_STALE_FENCE"
