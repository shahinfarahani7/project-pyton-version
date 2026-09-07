#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
INVENTORY = ROOT / "plan" / "evidence" / "phase-00-catalog-inventory.json"
CATALOG = ROOT / "src" / "shared" / "task-types" / "catalog.json"
MATRIX = ROOT / "dsl" / "policies" / "checkpoints" / "task-checkpoint-matrix-v1.yaml"

_CHECKPOINT_ENABLED = frozenset(
    {
        "text.summarize",
        "document.extract",
        "document.ocr",
        "ocr.receipt",
        "ocr.invoice",
        "ocr.simple_form",
        "ocr.product_label",
        "extract.amount",
        "extract.date",
        "extract.order_number",
        "extract.document_type",
        "llm.summary_verification",
        "llm.hallucination_check",
        "llm.ocr_output_validation",
        "llm.prompt_output_consistency",
    }
)


def classify_checkpoint(task_type: str) -> tuple[bool, str]:
    if task_type in _CHECKPOINT_ENABLED:
        if task_type == "text.summarize":
            return True, "chunk"
        if task_type.startswith(("ocr.", "extract.", "document.")):
            return True, "stage"
        return True, "chunk"
    return False, "none"


def main() -> int:
    inventory = json.loads(INVENTORY.read_text(encoding="utf-8"))
    entries: list[dict[str, object]] = []
    for item in inventory:
        task_type = str(item["taskTypeId"])
        enabled, strategy = classify_checkpoint(task_type)
        entry: dict[str, object] = {
            "taskType": task_type,
            "checkpointEnabled": enabled,
            "checkpointStrategy": strategy,
        }
        if enabled:
            entry["maximumIntervalSeconds"] = 60
        entries.append(entry)

    assert len(entries) == 56, f"expected 56 entries, got {len(entries)}"
    enabled_count = sum(1 for row in entries if row["checkpointEnabled"])
    assert enabled_count == len(_CHECKPOINT_ENABLED)

    matrix = {
        "apiVersion": "edgemint.io/v1",
        "kind": "CheckpointPolicyMatrix",
        "metadata": {
            "name": "task-checkpoint-matrix-v1",
            "version": "1.0.0",
            "status": "active",
            "description": "Section 28/46 checkpoint/resume defaults for all 56 catalog task types",
            "owners": ["platform", "mobile"],
        },
        "spec": {
            "defaultMaximumIntervalSeconds": 60,
            "mobileCheckpointPolicyRef": "CheckpointPolicy/mobile-checkpoint-v2@2.0.0",
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
            item["checkpointEnabled"] = row["checkpointEnabled"]
            item["checkpointStrategy"] = row["checkpointStrategy"]
            item["checkpointPolicyRef"] = "CheckpointPolicyMatrix/task-checkpoint-matrix-v1@1.0.0"
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        json.dumps(
            {
                "status": "ok",
                "entries": len(entries),
                "checkpointEnabledCount": enabled_count,
                "matrix": str(MATRIX.relative_to(ROOT)),
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
