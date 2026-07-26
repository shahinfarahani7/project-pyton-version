from __future__ import annotations

from collections.abc import Callable
from pathlib import Path
from typing import Any
from uuid import UUID

import yaml
from fastapi import Depends, Header, Request

from edgemint.security.context import AuthorizationContext, PrincipalContext, PrincipalKind
from edgemint.security.permissions import PermissionPolicy
from edgemint.security.problems import raise_auth_error
from edgemint.security.tokens import DelegatedTokenService


def load_operation_policies(root: Path | None = None) -> dict[str, PermissionPolicy]:
    base = root or Path(__file__).resolve().parents[4]
    contracts_dir = base / "dsl" / "operation-contracts"
    policies: dict[str, PermissionPolicy] = {}
    for path in sorted(contracts_dir.glob("*.yaml")):
        doc = yaml.safe_load(path.read_text(encoding="utf-8"))
        spec = doc.get("spec", {})
        operation_id = spec.get("operationId")
        permissions = tuple(spec.get("permissions") or [])
        if operation_id and permissions:
            policies[operation_id] = PermissionPolicy(operation_id=operation_id, permissions=permissions)
    return policies


OPERATION_POLICIES = load_operation_policies()


class AuthorizationDependency:
    def __init__(self, operation_id: str) -> None:
        self.operation_id = operation_id
        self.policy = OPERATION_POLICIES.get(operation_id)
        if self.policy is None:
            raise KeyError(f"missing authorization policy for operation: {operation_id}")

    async def __call__(
        self,
        request: Request,
        authorization: str | None = Header(default=None, alias="Authorization"),
        workspace_id_header: str | None = Header(default=None, alias="X-Workspace-Id"),
    ) -> AuthorizationContext:
        if not authorization or not authorization.startswith("Bearer "):
            raise_auth_error("AUTH_INVALID_CREDENTIAL")
        token = str(authorization).removeprefix("Bearer ").strip()
        policy = self.policy
        assert policy is not None
        claims = DelegatedTokenService().verify(token)
        if workspace_id_header and UUID(workspace_id_header) != claims.workspace_id:
            raise_auth_error("AUTH_WORKSPACE_MISMATCH", status=403)
        auth = DelegatedTokenService().to_authorization_context(claims)
        for permission in policy.permissions:
            auth.require_permission(permission)
        request.state.authorization = auth
        return auth


def require_operation(operation_id: str) -> Callable[..., Any]:
    return Depends(AuthorizationDependency(operation_id))


def development_principal(
    *,
    principal_id: UUID,
    workspace_id: UUID,
    permissions: frozenset[str],
) -> AuthorizationContext:
    return AuthorizationContext(
        principal=PrincipalContext(
            principal_id=principal_id,
            subject=str(principal_id),
            kind=PrincipalKind.USER,
            permissions=permissions,
        ),
        workspace_id=workspace_id,
        authorization_generation=1,
    )
