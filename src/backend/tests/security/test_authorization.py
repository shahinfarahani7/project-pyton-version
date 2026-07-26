from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID

import jwt
import pytest
from edgemint.building_blocks.settings import Settings
from edgemint.security.api_keys import generate_api_key, verify_api_key
from edgemint.security.context import AuthorizationContext, PrincipalContext, PrincipalKind
from edgemint.security.dependencies import OPERATION_POLICIES, load_operation_policies
from edgemint.security.permissions import PermissionPolicy, has_permission, parse_permission
from edgemint.security.tokens import DelegatedTokenService

pytestmark = pytest.mark.filterwarnings("ignore::jwt.InsecureKeyLengthWarning")
TEST_SIGNING_SECRET = "x" * 32


def test_parse_permission_accepts_namespaced_actions() -> None:
    assert parse_permission("customer.tasks:read") == ("customer.tasks", "read")


def test_has_permission_supports_namespace_wildcard() -> None:
    granted = frozenset({"customer.tasks:*"})
    assert has_permission(granted, "customer.tasks:read")
    assert not has_permission(granted, "billing.invoices:read")


def test_operation_policies_cover_all_contracts() -> None:
    policies = load_operation_policies()
    assert len(policies) == 141
    assert "searchTasks" in policies
    assert isinstance(policies["searchTasks"], PermissionPolicy)


def test_delegated_token_roundtrip() -> None:
    settings = Settings(_env_file=None, environment="test", jwt_signing_secret=TEST_SIGNING_SECRET)
    service = DelegatedTokenService(settings)
    principal_id = UUID(int=1)
    workspace_id = UUID(int=2)
    auth = AuthorizationContext(
        principal=PrincipalContext(
            principal_id=principal_id,
            subject=str(principal_id),
            kind=PrincipalKind.USER,
            permissions=frozenset({"customer.tasks:read"}),
        ),
        workspace_id=workspace_id,
        authorization_generation=3,
        session_id=UUID(int=4),
    )
    token = service.issue(auth=auth)
    claims = service.verify(token)
    assert claims.principal_id == principal_id
    assert claims.workspace_id == workspace_id
    assert claims.authorization_generation == 3
    assert "customer.tasks:read" in claims.permissions


def test_delegated_token_rejects_tampered_signature() -> None:
    settings = Settings(_env_file=None, environment="test", jwt_signing_secret=TEST_SIGNING_SECRET)
    service = DelegatedTokenService(settings)
    auth = AuthorizationContext(
        principal=PrincipalContext(
            principal_id=UUID(int=1),
            subject="user",
            kind=PrincipalKind.USER,
            permissions=frozenset({"customer.tasks:read"}),
        ),
        workspace_id=UUID(int=2),
        authorization_generation=1,
    )
    token = service.issue(auth=auth)
    header, payload, signature = token.split(".")
    tampered = jwt.encode({"sub": str(UUID(int=9))}, "wrong-secret", algorithm="HS256")
    with pytest.raises(jwt.PyJWTError):
        service.verify(tampered)
    assert signature
    assert header and payload


def test_api_key_hash_verification() -> None:
    raw, digest = generate_api_key()
    assert verify_api_key(raw, digest)
    assert not verify_api_key(raw + "x", digest)


def test_authorization_context_enforces_permissions() -> None:
    auth = AuthorizationContext(
        principal=PrincipalContext(
            principal_id=UUID(int=1),
            subject="user",
            kind=PrincipalKind.USER,
            permissions=frozenset({"customer.tasks:read"}),
        ),
        workspace_id=UUID(int=2),
        authorization_generation=1,
    )
    auth.require_permission("customer.tasks:read")
    with pytest.raises(PermissionError):
        auth.require_permission("customer.tasks:write")


def test_browser_session_record_active_window() -> None:
    from edgemint.security.tokens import BrowserSessionRecord

    now = datetime.now(UTC)
    record = BrowserSessionRecord(
        session_id=UUID(int=1),
        public_id="ses_test",
        principal_id=UUID(int=2),
        workspace_id=UUID(int=3),
        authorization_generation=1,
        risk_state="normal",
        revoked=False,
        absolute_expires_at=now + timedelta(hours=1),
        idle_expires_at=now + timedelta(minutes=30),
    )
    assert record.is_active(now)
    revoked = BrowserSessionRecord(
        session_id=record.session_id,
        public_id=record.public_id,
        principal_id=record.principal_id,
        workspace_id=record.workspace_id,
        authorization_generation=record.authorization_generation,
        risk_state=record.risk_state,
        revoked=True,
        absolute_expires_at=record.absolute_expires_at,
        idle_expires_at=record.idle_expires_at,
    )
    assert not revoked.is_active(now)


def test_cached_operation_policies_match_loader() -> None:
    assert len(OPERATION_POLICIES) == len(load_operation_policies())
