from __future__ import annotations

import json
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[4]
PROFILE = ROOT / "dsl" / "catalog" / "runtime-compatibility" / "production-v1.yaml"
SCHEMA = ROOT / "dsl" / "schemas" / "runtimecompatibilityprofile.schema.json"

ARCHITECTURE_RUNTIME_CLASSES = {
    "paddle_ocr",
    "mediapipe_llm",
    "image_classifier",
    "object_detector",
    "embedding_runtime",
    "vlm_runtime",
    "segmentation_runtime",
    "network_io",
    "system",
}


def test_runtime_compatibility_profile_validates_against_schema() -> None:
    document = yaml.safe_load(PROFILE.read_text(encoding="utf-8"))
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    errors = list(Draft202012Validator(schema).iter_errors(document))
    assert errors == []


def test_runtime_compatibility_profile_covers_section_59_classes() -> None:
    document = yaml.safe_load(PROFILE.read_text(encoding="utf-8"))
    recommended = set(document["spec"]["recommendedRuntimeClasses"])
    assert recommended == ARCHITECTURE_RUNTIME_CLASSES


def test_llm_and_ocr_cannot_co_run() -> None:
    document = yaml.safe_load(PROFILE.read_text(encoding="utf-8"))
    rule = next(
        item
        for item in document["spec"]["coRunRules"]
        if {item["runtimeA"], item["runtimeB"]} == {"mediapipe_llm", "paddle_ocr"}
    )
    assert rule["coRunAllowed"] is False
