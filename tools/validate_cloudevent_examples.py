#!/usr/bin/env python3
"""Validate every canonical CloudEvent example against its AsyncAPI message payload."""
from __future__ import annotations

import json
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parents[1]
ASYNCAPI_PATH = ROOT / "contracts" / "asyncapi" / "edgemint-events.yaml"
EXAMPLE_DIR = ROOT / "contracts" / "cloudevents"


def main() -> int:
    document = yaml.safe_load(ASYNCAPI_PATH.read_text(encoding="utf-8"))
    messages = document["components"]["messages"]
    by_type = {}
    for message_key, message in messages.items():
        type_value = None
        for branch in message.get("payload", {}).get("allOf", []):
            type_value = ((branch.get("properties") or {}).get("type") or {}).get("const") or type_value
        if not type_value:
            raise ValueError(f"Message has no canonical CloudEvent type: {message_key}")
        if type_value in by_type:
            raise ValueError(f"Duplicate CloudEvent type: {type_value}")
        by_type[type_value] = (message_key, message["payload"])
    errors: list[str] = []
    seen: set[str] = set()
    files = sorted(EXAMPLE_DIR.glob("*.json"))
    for path in files:
        example = json.loads(path.read_text(encoding="utf-8"))
        event_type = example.get("type")
        if event_type in seen:
            errors.append(f"{path.name}:duplicate example type:{event_type}")
            continue
        seen.add(event_type)
        if event_type not in by_type:
            errors.append(f"{path.name}:unknown event type:{event_type}")
            continue
        message_key, payload = by_type[event_type]
        wrapper = {
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "allOf": [payload],
            "components": document.get("components", {}),
        }
        validator = Draft202012Validator(wrapper, format_checker=FormatChecker())
        for issue in sorted(validator.iter_errors(example), key=lambda e: list(e.absolute_path)):
            location = "/".join(str(x) for x in issue.absolute_path) or "root"
            errors.append(f"{path.name}:{message_key}:{location}:{issue.message}")
    missing = sorted(set(by_type) - seen)
    extra = sorted(seen - set(by_type))
    if missing:
        errors.append(f"missing examples:{missing[:20]}")
    if extra:
        errors.append(f"extra examples:{extra[:20]}")
    result = {"status": "passed" if not errors else "failed", "messages": len(messages), "examples": len(files), "errors": errors}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
