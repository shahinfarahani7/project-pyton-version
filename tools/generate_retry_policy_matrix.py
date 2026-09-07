#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
INVENTORY = ROOT / "plan" / "evidence" / "phase-00-catalog-inventory.json"
CATALOG = ROOT / "src" / "shared" / "task-types" / "catalog.json"
MATRIX = ROOT / "dsl" / "policies" / "retry" / "task-retry-matrix-v1.yaml"

_FLEX_NO_CONTRACT = frozenset()

_STRONGER_WORKER = frozenset(
    {
        "text.summarize",
        "text.classify",
        "moderation.prompt_safety",
        "moderation.text",
        "moderation.profanity",
        "moderation.spam_comment",
        "review.fake_detection",
        "review.sentiment",
        "review.topic_tagging",
        "llm.summary_verification",
        "llm.hallucination_check",
        "llm.ocr_output_validation",
        "llm.policy_violation",
        "llm.prompt_output_consistency",
        "llm.answer_quality_score",
        "llm.suspicious_output",
        "nlp.language_detection",
        "nlp.text_classification",
        "nlp.spam_fraud_classification",
        "ml.bot_abuse_risk",
        "catalog.fake_listing",
        "llm.ai_tag_validation",
        "llm.caption_validation",
        "dataset.label_verification",
        "dataset.duplicate_cleanup",
        "dataset.low_quality_removal",
        "ml.active_learning_prelabel",
        "ml.consensus_label_validation",
        "ml.human_verification_quality",
    }
)


def classify_task(task_type: str, detail: str) -> tuple[str, bool]:
    if task_type in _FLEX_NO_CONTRACT or detail == "flex_no_contract":
        return "no_retry", False
    if task_type in _STRONGER_WORKER:
        return "stronger_worker", True
    return "immediate_other_worker", True


def quality_failure_class(default_class: str) -> str:
    if default_class == "no_retry":
        return "no_retry"
    if default_class == "stronger_worker":
        return "stronger_worker"
    return "stronger_worker"


def main() -> int:
    inventory = json.loads(INVENTORY.read_text(encoding="utf-8"))
    entries: list[dict[str, object]] = []
    for item in inventory:
        task_type = str(item["taskTypeId"])
        retry_class, executable = classify_task(task_type, str(item.get("detail", "")))
        entry: dict[str, object] = {
            "taskType": task_type,
            "retryClass": retry_class,
            "executable": executable,
            "qualityFailureRetryClass": quality_failure_class(retry_class),
        }
        if retry_class != "no_retry":
            entry["maxAutomaticRetries"] = 2
        entries.append(entry)

    assert len(entries) == 56, f"expected 56 entries, got {len(entries)}"

    matrix = {
        "apiVersion": "edgemint.io/v1",
        "kind": "RetryPolicyMatrix",
        "metadata": {
            "name": "task-retry-matrix-v1",
            "version": "1.0.0",
            "status": "active",
            "description": "Section 43/55 retry routing defaults for all 56 catalog task types",
            "owners": ["platform", "ml"],
        },
        "spec": {
            "defaultMaxAutomaticRetries": 2,
            "entries": sorted(entries, key=lambda row: str(row["taskType"])),
        },
    }
    MATRIX.parent.mkdir(parents=True, exist_ok=True)
    MATRIX.write_text(yaml.safe_dump(matrix, sort_keys=False, allow_unicode=True), encoding="utf-8")

    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    by_type = {str(row["taskType"]): row for row in entries}
    for category in catalog["categories"]:
        for item in category["types"]:
            task_type = str(item["value"])
            row = by_type[task_type]
            item["retryClass"] = row["retryClass"]
            item["executable"] = row["executable"]
            item["retryPolicyRef"] = "RetryPolicyMatrix/task-retry-matrix-v1@1.0.0"
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": "ok", "entries": len(entries), "matrix": str(MATRIX.relative_to(ROOT))}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
