#!/usr/bin/env python3
"""Shared JSON Schema helpers for deterministic contract example validation."""
from __future__ import annotations

import copy
import re
from typing import Any


def resolve_ref(document: dict[str, Any], ref: str) -> dict[str, Any]:
    if not ref.startswith("#/"):
        raise ValueError(f"Only local references are supported: {ref}")
    node: Any = document
    for token in ref[2:].split("/"):
        token = token.replace("~1", "/").replace("~0", "~")
        node = node[token]
    if not isinstance(node, dict):
        raise ValueError(f"Reference does not resolve to an object: {ref}")
    return node


def dereference(document: dict[str, Any], schema: dict[str, Any], seen: set[str] | None = None) -> dict[str, Any]:
    seen = set() if seen is None else set(seen)
    if "$ref" in schema:
        ref = schema["$ref"]
        if ref in seen:
            return {}
        seen.add(ref)
        base = dereference(document, resolve_ref(document, ref), seen)
        overlay = {k: v for k, v in schema.items() if k != "$ref"}
        return merge_schemas(base, dereference(document, overlay, seen))
    if "allOf" in schema:
        merged: dict[str, Any] = {}
        for child in schema["allOf"]:
            merged = merge_schemas(merged, dereference(document, child, seen))
        overlay = {k: v for k, v in schema.items() if k != "allOf"}
        return merge_schemas(merged, dereference(document, overlay, seen))
    return copy.deepcopy(schema)


def merge_schemas(left: dict[str, Any], right: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(left)
    for key, value in right.items():
        if key == "properties":
            result.setdefault(key, {})
            result[key].update(copy.deepcopy(value))
        elif key == "required":
            result[key] = list(dict.fromkeys([*result.get(key, []), *value]))
        elif key in {"allOf", "oneOf", "anyOf"}:
            result[key] = copy.deepcopy(value)
        elif isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = merge_schemas(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


def _string_example(schema: dict[str, Any], name: str) -> str:
    if "const" in schema:
        return str(schema["const"])
    if schema.get("enum"):
        return str(schema["enum"][0])
    if "example" in schema:
        return str(schema["example"])
    fmt = schema.get("format")
    lowered = name.lower()
    if fmt == "date-time":
        return "2026-07-21T10:00:00Z"
    if fmt == "date":
        return "2026-07-21"
    if fmt in {"uri", "url", "uri-reference"}:
        return "https://example.invalid/resource"
    if fmt == "email":
        return "user@example.invalid"
    if fmt == "uuid":
        return "0190f5a0-7b3c-7a11-8b00-000000000001"
    pattern = schema.get("pattern", "")
    if "sha256" in lowered or "digest" in lowered or "^[a-f0-9]{64}$" in pattern:
        return "a" * 64
    if lowered in {"id", "publicid", "organizationid", "workspaceid", "taskid", "fileid", "quoteid", "modelid", "workerid", "deviceid", "assignmentid", "attemptid", "resultid", "memberid", "endpointid"} or lowered.endswith("id"):
        prefixes = {
            "organizationid": "org", "workspaceid": "wsp", "taskid": "tsk", "fileid": "fil",
            "quoteid": "qte", "modelid": "mdl", "workerid": "wrk", "deviceid": "dev",
            "assignmentid": "asn", "attemptid": "att", "resultid": "res", "endpointid": "whk",
            "operationid": "opn", "requestid": "req", "correlationid": "cor", "causationid": "cau",
        }
        prefix = prefixes.get(lowered, "id")
        return f"{prefix}_01J00000000000000000000000"
    if "currency" in lowered:
        return "EUR"
    if "country" in lowered:
        return "DE"
    if "locale" in lowered or "language" in lowered:
        return "en"
    if "contenttype" in lowered or "media" in lowered:
        return "application/json"
    if "name" in lowered:
        return "Example Name"
    if "description" in lowered:
        return "Deterministic contract example."
    if "status" in lowered:
        return "active"
    minimum = int(schema.get("minLength", 1))
    value = "example"
    if len(value) < minimum:
        value += "x" * (minimum - len(value))
    maximum = schema.get("maxLength")
    if maximum is not None:
        value = value[: int(maximum)]
    if pattern:
        # Handle the package's common anchored patterns without inventing arbitrary regex generation.
        if name.lower() == "pagerange" or pattern.startswith("^(?:all|"):
            value = "all"
        elif pattern.startswith("^req_"):
            value = "req_01J00000000000000000000000"
        elif pattern.startswith("^EM-"):
            value = "EM-20260721-ABCDEF"
        elif "acct_" in pattern:
            value = "acct_Example123"
        elif pattern.startswith("^Z"):
            value = "ZEXAMPLE123"
    return value


def example_for_schema(document: dict[str, Any], schema: dict[str, Any], name: str = "value", depth: int = 0) -> Any:
    if depth > 40:
        raise ValueError(f"Schema recursion too deep at {name}")
    schema = dereference(document, schema)
    if "const" in schema:
        return copy.deepcopy(schema["const"])
    if schema.get("type") == "string" and schema.get("pattern") == "^[a-z][a-z0-9_]{1,31}_[0-9A-HJKMNP-TV-Z]{26}$":
        return _string_example({k: v for k, v in schema.items() if k != "example"}, name)
    if "example" in schema:
        return copy.deepcopy(schema["example"])
    if "default" in schema:
        return copy.deepcopy(schema["default"])
    if schema.get("enum"):
        return copy.deepcopy(schema["enum"][0])
    if "oneOf" in schema:
        return example_for_schema(document, schema["oneOf"][0], name, depth + 1)
    if "anyOf" in schema:
        candidates = [x for x in schema["anyOf"] if x.get("type") != "null"] or schema["anyOf"]
        return example_for_schema(document, candidates[0], name, depth + 1)
    type_value = schema.get("type")
    if isinstance(type_value, list):
        type_value = next((x for x in type_value if x != "null"), "null")
    if type_value is None:
        if "properties" in schema or "required" in schema:
            type_value = "object"
        elif "items" in schema:
            type_value = "array"
        else:
            type_value = "string"
    if type_value == "object":
        properties = schema.get("properties", {})
        required = schema.get("required", [])
        output: dict[str, Any] = {}
        for prop in required:
            output[prop] = example_for_schema(document, properties.get(prop, {}), prop, depth + 1)
        # Include a few useful optional response fields while remaining deterministic.
        for prop in ("createdAt", "updatedAt", "occurredAt", "page", "items", "nextCursor"):
            if prop in properties and prop not in output:
                output[prop] = example_for_schema(document, properties[prop], prop, depth + 1)
        return output
    if type_value == "array":
        minimum = max(1 if name == "items" else 0, int(schema.get("minItems", 0)))
        count = min(max(minimum, 1), 2)
        return [example_for_schema(document, schema.get("items", {}), name.rstrip("s") or "item", depth + 1) for _ in range(count)]
    if type_value == "integer":
        if "const" in schema:
            return int(schema["const"])
        return int(schema.get("minimum", 1))
    if type_value == "number":
        return float(schema.get("minimum", 1.0))
    if type_value == "boolean":
        return True
    if type_value == "null":
        return None
    return _string_example(schema, name)


def operation_index(document: dict[str, Any]) -> dict[str, tuple[str, str, dict[str, Any]]]:
    output: dict[str, tuple[str, str, dict[str, Any]]] = {}
    for path, path_item in document.get("paths", {}).items():
        for method, operation in path_item.items():
            if method.lower() not in {"get", "post", "put", "patch", "delete"} or not isinstance(operation, dict):
                continue
            operation_id = operation.get("operationId")
            if operation_id:
                output[operation_id] = (method.upper(), path, operation)
    return output
