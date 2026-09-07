from __future__ import annotations

import json
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[4]
POLICY = ROOT / "dsl" / "policies" / "scheduling" / "production-exclusive-groups-v1.yaml"
SCHEMA = ROOT / "dsl" / "schemas" / "exclusivegrouppolicy.schema.json"


def test_exclusive_group_policy_validates_against_schema() -> None:
    document = yaml.safe_load(POLICY.read_text(encoding="utf-8"))
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    errors = list(Draft202012Validator(schema).iter_errors(document))
    assert errors == []


def test_llm_and_ocr_exclusive_groups_documented() -> None:
    document = yaml.safe_load(POLICY.read_text(encoding="utf-8"))
    group_ids = {group["id"] for group in document["spec"]["groups"]}
    assert {"llm_inference", "ocr_inference"}.issubset(group_ids)
    llm = next(group for group in document["spec"]["groups"] if group["id"] == "llm_inference")
    ocr = next(group for group in document["spec"]["groups"] if group["id"] == "ocr_inference")
    assert llm["maximumConcurrentReservationsPerDevice"] == 1
    assert ocr["maximumConcurrentReservationsPerDevice"] == 1
    assert ocr["certifiedMaximumConcurrentReservationsPerDevice"] == 2


def test_qwen_ocr_cross_group_rule_blocks_concurrency_by_default() -> None:
    document = yaml.safe_load(POLICY.read_text(encoding="utf-8"))
    rule = next(
        item
        for item in document["spec"]["crossGroupRules"]
        if {item["groupA"], item["groupB"]} == {"llm_inference", "ocr_inference"}
    )
    assert rule["concurrentAllowed"] is False
    assert rule["certificationRequired"] is True
