#!/usr/bin/env python3
"""Strictly validate every operation sample against its OpenAPI operation and schemas."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft202012Validator, FormatChecker

from schema_utils import operation_index, resolve_ref

ROOT = Path(__file__).resolve().parents[1]
API_DIR = ROOT / "contracts" / "openapi"
SAMPLE_DIR = ROOT / "samples" / "by-operation"


def deref(document: dict[str, Any], value: dict[str, Any]) -> dict[str, Any]:
    while isinstance(value, dict) and "$ref" in value:
        resolved = resolve_ref(document, value["$ref"])
        value = {**resolved, **{k: v for k, v in value.items() if k != "$ref"}}
    return value


def validator(document: dict[str, Any], schema: dict[str, Any]) -> Draft202012Validator:
    # Validate through a JSON Schema wrapper so internal OpenAPI component references
    # resolve from the wrapper root without the deprecated RefResolver API.
    wrapper = {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "allOf": [schema],
        "components": document.get("components", {}),
    }
    return Draft202012Validator(wrapper, format_checker=FormatChecker())


def validate_value(document: dict[str, Any], schema: dict[str, Any], value: Any, label: str, errors: list[str]) -> None:
    for issue in sorted(validator(document, schema).iter_errors(value), key=lambda e: list(e.absolute_path)):
        location = "/".join(str(x) for x in issue.absolute_path) or "root"
        errors.append(f"{label}:{location}:{issue.message}")


def main() -> int:
    apis: dict[str, dict[str, Any]] = {}
    indexes = {}
    for path in sorted(API_DIR.glob("*.yaml")):
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
        apis[path.stem] = document
        indexes[path.stem] = operation_index(document)
    errors: list[str] = []
    seen: set[tuple[str, str]] = set()
    files = sorted(SAMPLE_DIR.glob("*.json"))
    for path in files:
        sample = json.loads(path.read_text(encoding="utf-8"))
        api_name, operation_id = sample.get("api"), sample.get("operationId")
        key = (api_name, operation_id)
        if key in seen:
            errors.append(f"{path.name}:duplicate operation sample:{key}")
            continue
        seen.add(key)
        if api_name not in apis or operation_id not in indexes.get(api_name, {}):
            errors.append(f"{path.name}:unknown operation:{api_name}:{operation_id}")
            continue
        document = apis[api_name]
        method, route, operation = indexes[api_name][operation_id]
        request = sample.get("request", {})
        if request.get("method") != method or request.get("path") != route:
            errors.append(f"{path.name}:method/path mismatch")
        # Validate operation parameters from path-level and operation-level definitions.
        path_item = document["paths"][route]
        parameters = [*path_item.get("parameters", []), *operation.get("parameters", [])]
        locations = {"path": "pathParameters", "query": "query", "header": "headers"}
        seen_parameters = set()
        for raw_parameter in parameters:
            parameter = deref(document, raw_parameter)
            where, name = parameter.get("in"), parameter.get("name")
            parameter_key = (where, (name or "").lower())
            if parameter_key in seen_parameters:
                continue
            seen_parameters.add(parameter_key)
            if where not in locations or not name:
                continue
            values = request.get(locations[where], {})
            actual_name = name
            if where == "header":
                match = next((k for k in values if k.lower() == name.lower()), None)
                actual_name = match or name
            if parameter.get("required") and actual_name not in values:
                errors.append(f"{path.name}:request parameter missing:{where}:{name}")
            elif actual_name in values and parameter.get("schema"):
                validate_value(document, parameter["schema"], values[actual_name], f"{path.name}:parameter:{where}:{name}", errors)
        body_definition = operation.get("requestBody")
        if body_definition:
            body_definition = deref(document, body_definition)
            media = (body_definition.get("content") or {}).get("application/json")
            body = request.get("body")
            if body_definition.get("required") and body is None:
                errors.append(f"{path.name}:request body missing")
            if media and body is not None:
                validate_value(document, media["schema"], body, f"{path.name}:request", errors)
        elif request.get("body") is not None:
            errors.append(f"{path.name}:unexpected request body")
        status = str(sample.get("expected", {}).get("successStatus"))
        response = (operation.get("responses") or {}).get(status)
        if response is None:
            errors.append(f"{path.name}:unknown success status:{status}")
            continue
        response = deref(document, response)
        media = (response.get("content") or {}).get("application/json")
        body = sample.get("expected", {}).get("successBody")
        if media:
            validate_value(document, media["schema"], body, f"{path.name}:response:{status}", errors)
        elif body is not None:
            errors.append(f"{path.name}:unexpected response body:{status}")
        declared = set(operation.get("x-required-permissions", []))
        sampled = set(sample.get("expected", {}).get("requiredPermissions", []))
        if declared != sampled:
            errors.append(f"{path.name}:permission mismatch:{sorted(declared)}!={sorted(sampled)}")
    operation_total = sum(len(index) for index in indexes.values())
    if len(seen) != operation_total:
        missing = sorted((api, op) for api, idx in indexes.items() for op in idx if (api, op) not in seen)
        errors.append(f"missing operation samples:{missing[:20]}")
    result = {"status": "passed" if not errors else "failed", "samples": len(files), "operations": operation_total, "errors": errors}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
