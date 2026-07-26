#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any
import yaml

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []
operation_ids: list[str] = []


def walk(value: Any):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def resolve_pointer(doc: dict[str, Any], pointer: str) -> bool:
    if not pointer.startswith("#/"):
        return True
    current: Any = doc
    for token in pointer[2:].split("/"):
        token = token.replace("~1", "/").replace("~0", "~")
        if not isinstance(current, dict) or token not in current:
            return False
        current = current[token]
    return True


openapi_docs: dict[str, dict[str, Any]] = {}
for path in sorted((ROOT / "contracts/openapi").glob("*.yaml")):
    doc = yaml.safe_load(path.read_text(encoding="utf-8"))
    openapi_docs[path.name] = doc
    if not str(doc.get("openapi", "")).startswith("3.1"):
        errors.append(f"{path.name}: OpenAPI must be 3.1")
    if not doc.get("security"):
        errors.append(f"{path.name}: root security is required")
    for node in walk(doc):
        ref = node.get("$ref") if isinstance(node, dict) else None
        if ref and ref.startswith("#/") and not resolve_pointer(doc, ref):
            errors.append(f"{path.name}: unresolved local ref {ref}")
    for route, item in doc.get("paths", {}).items():
        for method, operation in item.items():
            if method not in {"get", "post", "put", "patch", "delete"}:
                continue
            operation_id = operation.get("operationId")
            if not operation_id:
                errors.append(f"{path.name} {method} {route}: missing operationId")
            elif operation_id in operation_ids:
                errors.append(f"duplicate operationId {operation_id}")
            else:
                operation_ids.append(operation_id)
            if not operation.get("summary"):
                errors.append(f"{path.name} {operation_id}: missing summary")
            if operation_id and not re.fullmatch(r"[a-z][A-Za-z0-9]*", operation_id):
                errors.append(f"{path.name} {operation_id}: operationId must be lowerCamelCase")
            if not operation.get("tags"):
                errors.append(f"{path.name} {operation_id}: missing tags")
            permissions = operation.get("x-required-permissions")
            if not isinstance(permissions, list) or not permissions or len(permissions) != len(set(permissions)):
                errors.append(f"{path.name} {operation_id}: x-required-permissions must be a nonempty unique list")
            elif any(not re.fullmatch(r"[a-z0-9_.-]+:[a-z0-9_.-]+", x) for x in permissions):
                errors.append(f"{path.name} {operation_id}: invalid permission syntax")
            if method in {"post", "put", "patch", "delete"}:
                refs = [x.get("$ref", "") for x in operation.get("parameters", []) if isinstance(x, dict)]
                if not any("IdempotencyKey" in x for x in refs):
                    errors.append(f"{path.name} {method} {route}: mutation missing Idempotency-Key")
            responses = operation.get("responses", {})
            if not responses:
                errors.append(f"{path.name} {operation_id}: missing responses")
            if not any(str(code).startswith("2") for code in responses):
                errors.append(f"{path.name} {operation_id}: missing success response")

public = openapi_docs.get("edgemint-public-api.yaml", {})
task = public.get("components", {}).get("schemas", {}).get("Task", {})
task_props = task.get("properties", {})
if "status" in task_props:
    errors.append("public API Task must not contain ambiguous status")
for field in ["lifecycleStatus", "executionStatus", "billingStatus"]:
    if field not in task_props or field not in task.get("required", []):
        errors.append(f"public API Task missing required {field}")
expected_lifecycle = {"draft", "submitted", "active", "completed", "failed", "cancelled", "expired", "disputed"}
if set(task_props.get("lifecycleStatus", {}).get("enum", [])) != expected_lifecycle:
    errors.append("public API lifecycleStatus differs from task DSL")

# Canonical EventCatalog is the sole source of event names and types.
event_catalog = yaml.safe_load((ROOT / "dsl/catalog/events/event-catalog-v2.yaml").read_text(encoding="utf-8"))
catalog_events = event_catalog["spec"]["events"]
catalog_types = {event["type"] for event in catalog_events}
if len(catalog_types) != len(catalog_events):
    errors.append("EventCatalog contains duplicate types")

cloud_files = sorted((ROOT / "contracts/cloudevents").glob("*.json"))
cloud_types: set[str] = set()
cloud_ids: set[str] = set()
required_cloud_fields = ["specversion", "id", "source", "type", "subject", "time", "tenantId", "correlationId", "causationId", "partitionKey", "schemaVersion", "data"]
for path in cloud_files:
    event = json.loads(path.read_text(encoding="utf-8"))
    for field in required_cloud_fields:
        if field not in event:
            errors.append(f"{path.name}: missing {field}")
    if event.get("id") in cloud_ids:
        errors.append(f"{path.name}: duplicate event id {event.get('id')}")
    cloud_ids.add(event.get("id"))
    if event.get("type") in cloud_types:
        errors.append(f"{path.name}: duplicate event type {event.get('type')}")
    cloud_types.add(event.get("type"))
    expected_file = next((x for x in catalog_events if x["type"] == event.get("type")), None)
    if expected_file and path.name != expected_file["name"] + ".json":
        errors.append(f"{path.name}: filename must match canonical event name {expected_file['name']}.json")

async_doc = yaml.safe_load((ROOT / "contracts/asyncapi/edgemint-events.yaml").read_text(encoding="utf-8"))
if async_doc.get("asyncapi") != "3.0.0":
    errors.append("AsyncAPI must be 3.0.0")
for node in walk(async_doc):
    ref = node.get("$ref") if isinstance(node, dict) else None
    if ref and ref.startswith("#/") and not resolve_pointer(async_doc, ref):
        errors.append(f"AsyncAPI unresolved local ref {ref}")
async_messages = async_doc.get("components", {}).get("messages", {})
async_types: set[str] = set()
for key, message in async_messages.items():
    try:
        event_type = message["payload"]["allOf"][1]["properties"]["type"]["const"]
    except Exception:
        errors.append(f"AsyncAPI message {key}: missing canonical type const")
        continue
    if event_type in async_types:
        errors.append(f"AsyncAPI duplicate event type {event_type}")
    async_types.add(event_type)
channels = async_doc.get("channels", {})
operations = async_doc.get("operations", {})
if len(channels) != len(catalog_types) or len(async_messages) != len(catalog_types) or len(operations) != len(catalog_types):
    errors.append("AsyncAPI channel/message/operation counts must equal EventCatalog")
if cloud_types != catalog_types:
    errors.append(f"CloudEvent types differ from catalog: missing={sorted(catalog_types-cloud_types)}, extra={sorted(cloud_types-catalog_types)}")
if async_types != catalog_types:
    errors.append(f"AsyncAPI types differ from catalog: missing={sorted(catalog_types-async_types)}, extra={sorted(async_types-catalog_types)}")

print(json.dumps({
    "operationIds": len(operation_ids),
    "canonicalEvents": len(catalog_types),
    "cloudEventExamples": len(cloud_files),
    "asyncChannels": len(channels),
    "errors": len(errors),
}, indent=2))
if errors:
    print("\n".join(errors[:500]))
    sys.exit(1)
