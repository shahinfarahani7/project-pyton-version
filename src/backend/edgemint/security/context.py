from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum
from uuid import UUID


class PrincipalKind(StrEnum):
    USER = "user"
    SERVICE = "service"
    WORKER = "worker"
    OPERATOR = "operator"


@dataclass(frozen=True, slots=True)
class PrincipalContext:
    principal_id: UUID
    subject: str
    kind: PrincipalKind
    permissions: frozenset[str] = field(default_factory=frozenset)


@dataclass(frozen=True, slots=True)
class AuthorizationContext:
    principal: PrincipalContext
    workspace_id: UUID
    authorization_generation: int
    session_id: UUID | None = None
    correlation_id: str | None = None
    request_id: str | None = None

    def require_permission(self, permission: str) -> None:
        from .permissions import has_permission

        if not has_permission(self.principal.permissions, permission):
            raise PermissionError(permission)
