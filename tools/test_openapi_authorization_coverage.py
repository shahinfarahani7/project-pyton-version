#!/usr/bin/env python3
"""Verify every OpenAPI operation has matching authorization metadata and policy coverage."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
CONTRACTS = ROOT / "dsl" / "operation-contracts"
OPENAPI = ROOT / "contracts" / "openapi"
POLICY_MODULE = ROOT / "src" / "backend" / "edgemint" / "security" / "dependencies.py"
PERMISSION_PATTERN = re.compile(r"^[a-z0-9_.-]+:[a-z0-9_.-]+$")


def load_contract_policies() -> dict[str, tuple[str, ...]]:
    policies: dict[str, tuple[str, ...]] = {}
    for path in sorted(CONTRACTS.glob("*.yaml")):
        doc = yaml.safe_load(path.read_text(encoding="utf-8"))
        spec = doc.get("spec", {})
        operation_id = spec.get("operationId")
        permissions = tuple(spec.get("permissions") or [])
        if operation_id:
            policies[operation_id] = permissions
    return policies


def load_openapi_permissions() -> dict[str, list[str]]:
    permissions: dict[str, list[str]] = {}
    for path in sorted(OPENAPI.glob("*.yaml")):
        doc = yaml.safe_load(path.read_text(encoding="utf-8"))
        for route_item in doc.get("paths", {}).values():
            for method, operation in route_item.items():
                if method not in {"get", "post", "put", "patch", "delete"}:
                    continue
                operation_id = operation.get("operationId")
                if operation_id:
                    permissions[operation_id] = list(operation.get("x-required-permissions") or [])
    return permissions


def main() -> int:
    errors: list[str] = []
    contract_policies = load_contract_policies()
    openapi_permissions = load_openapi_permissions()

    if not POLICY_MODULE.exists():
        errors.append("missing authorization dependency module")

    for operation_id, permissions in contract_policies.items():
        if not permissions:
            errors.append(f"{operation_id}: operation contract missing permissions")
            continue
        for permission in permissions:
            if not PERMISSION_PATTERN.fullmatch(permission):
                errors.append(f"{operation_id}: invalid permission {permission}")
        openapi = openapi_permissions.get(operation_id)
        if openapi is None:
            errors.append(f"{operation_id}: missing OpenAPI operation")
        elif set(openapi) != set(permissions):
            errors.append(
                f"{operation_id}: OpenAPI permissions {openapi} != contract permissions {list(permissions)}"
            )

    for operation_id in sorted(set(openapi_permissions) - set(contract_policies)):
        errors.append(f"{operation_id}: OpenAPI operation missing operation contract policy")

    result = {
        "status": "passed" if not errors else "failed",
        "operationContracts": len(contract_policies),
        "openApiOperations": len(openapi_permissions),
        "errors": errors,
    }
    print(json.dumps(result, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
