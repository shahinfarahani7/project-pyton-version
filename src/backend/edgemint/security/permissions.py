from __future__ import annotations

import re
from dataclasses import dataclass

PERMISSION_PATTERN = re.compile(r"^[a-z0-9_.-]+:[a-z0-9_.-]+$")


@dataclass(frozen=True, slots=True)
class PermissionPolicy:
    operation_id: str
    permissions: tuple[str, ...]

    def __post_init__(self) -> None:
        if not self.permissions:
            raise ValueError("permission policy must declare at least one permission")
        for permission in self.permissions:
            parse_permission(permission)


def parse_permission(value: str) -> tuple[str, str]:
    if not PERMISSION_PATTERN.fullmatch(value):
        raise ValueError(f"invalid permission syntax: {value}")
    namespace, action = value.split(":", 1)
    return namespace, action


def has_permission(granted: frozenset[str] | set[str], required: str) -> bool:
    parse_permission(required)
    if required in granted:
        return True
    namespace, _ = parse_permission(required)
    wildcard = f"{namespace}:*"
    return wildcard in granted
