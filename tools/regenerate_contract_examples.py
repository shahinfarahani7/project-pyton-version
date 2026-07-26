#!/usr/bin/env python3
"""Regenerate deterministic request/response examples from canonical OpenAPI schemas."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import yaml

from schema_utils import example_for_schema, operation_index, resolve_ref

ROOT = Path(__file__).resolve().parents[1]
API_DIR = ROOT / "contracts" / "openapi"
SAMPLE_DIR = ROOT / "samples" / "by-operation"


def load_apis() -> dict[str, dict[str, Any]]:
    result = {}
    for path in sorted(API_DIR.glob("*.yaml")):
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
        result[path.stem] = document
    return result


def request_schema(operation: dict[str, Any]) -> dict[str, Any] | None:
    body = operation.get("requestBody")
    if not body:
        return None
    media = (body.get("content") or {}).get("application/json")
    return None if not media else media.get("schema")


def response_schema(operation: dict[str, Any], status: str) -> dict[str, Any] | None:
    response = (operation.get("responses") or {}).get(str(status))
    if not response:
        return None
    media = (response.get("content") or {}).get("application/json")
    return None if not media else media.get("schema")


def semantic_overrides(operation_id: str, sample: dict[str, Any]) -> None:
    if operation_id == "createTask":
        body = sample["request"]["body"]
        body["workspaceId"] = "wsp_01J00000000000000000000000"
        body["taskType"] = "document-ocr"
        body["input"] = {
            "fileId": "fil_01J00000000000000000000000",
            "contentType": "application/pdf",
        }
        body["configuration"] = {
            "language": ["en"],
            "outputFormat": "structured_json",
            "verificationLevel": "verified",
            "priority": "standard",
            "regionPolicy": "eu_only",
            "retentionDays": 30,
            "parameters": {"pageRange": "all", "deskew": True},
        }
        success = sample["expected"]["successBody"]
        for key, value in {
            "lifecycleStatus": "submitted",
            "executionStatus": "queued",
            "billingStatus": "reserved",
        }.items():
            if key in success:
                success[key] = value
    elif operation_id in {"quoteTask", "createQuote"}:
        body = sample["request"].get("body") or {}
        if "taskType" in body:
            body["taskType"] = "document-ocr"


def main() -> int:
    apis = load_apis()
    indexes = {name: operation_index(doc) for name, doc in apis.items()}
    changed = 0
    for path in sorted(SAMPLE_DIR.glob("*.json")):
        sample = json.loads(path.read_text(encoding="utf-8"))
        api_name = sample["api"]
        operation_id = sample["operationId"]
        document = apis[api_name]
        method, route, operation = indexes[api_name][operation_id]
        sample["request"]["method"] = method
        sample["request"]["path"] = route
        path_item = document["paths"][route]
        seen_parameters = set()
        for raw_parameter in [*path_item.get("parameters", []), *operation.get("parameters", [])]:
            parameter = raw_parameter
            while "$ref" in parameter:
                parameter = resolve_ref(document, parameter["$ref"])
            key = (parameter.get("in"), parameter.get("name", "").lower())
            if key in seen_parameters:
                continue
            seen_parameters.add(key)
            where, parameter_name = parameter.get("in"), parameter.get("name")
            if not parameter_name or where not in {"path", "query", "header"}:
                continue
            target_key = {"path": "pathParameters", "query": "query", "header": "headers"}[where]
            target = sample["request"].setdefault(target_key, {})
            if parameter.get("required") or parameter_name in target:
                value = example_for_schema(document, parameter.get("schema", {}), parameter_name)
                if parameter_name.lower() == "authorization":
                    value = "Bearer access_token_redacted"
                elif parameter_name.lower() == "if-match":
                    value = '"1"'
                elif parameter_name.lower() == "idempotency-key":
                    value = f"idem_{operation_id}_0001"
                elif parameter_name.lower() == "x-request-id":
                    value = f"req_{operation_id}_0001"
                target[parameter_name] = value
        req_schema = request_schema(operation)
        if req_schema is not None:
            sample["request"]["body"] = example_for_schema(document, req_schema, "request")
        else:
            sample["request"]["body"] = None
        status = str(sample["expected"]["successStatus"])
        res_schema = response_schema(operation, status)
        if res_schema is not None:
            sample["expected"]["successBody"] = example_for_schema(document, res_schema, "response")
        else:
            sample["expected"]["successBody"] = None
        semantic_overrides(operation_id, sample)
        new_text = json.dumps(sample, ensure_ascii=False, indent=2) + "\n"
        if path.read_text(encoding="utf-8") != new_text:
            path.write_text(new_text, encoding="utf-8")
            changed += 1
    print(json.dumps({"status": "regenerated", "samples": len(list(SAMPLE_DIR.glob('*.json'))), "changed": changed}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
