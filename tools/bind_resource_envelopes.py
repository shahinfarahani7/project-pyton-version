#!/usr/bin/env python3
"""Bind TaskResourceEnvelope refs to all 56 catalog task types (P2-T06)."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "src/shared/task-types/catalog.json"
BINDINGS_OUT = ROOT / "plan/evidence/phase-02-resource-envelope-bindings.json"

# Default envelope template per task type id.
ENVELOPE_BY_TASK: dict[str, str] = {}

OCR_TYPES = {
    "document.ocr",
    "ocr.receipt",
    "ocr.invoice",
    "ocr.simple_form",
    "ocr.product_label",
}
EXTRACT_TYPES = {
    "document.extract",
    "extract.amount",
    "extract.date",
    "extract.order_number",
    "extract.document_type",
}
SUMMARIZE_TYPES = {"text.summarize", "llm.summary_verification"}
VISION_TYPES = {
    "image.classify",
    "image.remove_background",
    "safety.nsfw_detection",
    "safety.violence_detection",
    "safety.weapon_detection",
    "safety.unsafe_image",
    "moderation.profile_image",
    "moderation.generated_image",
    "quality.document_image",
    "quality.blurry_image",
    "catalog.image_tagging",
    "catalog.product_classification",
    "catalog.duplicate_image",
    "catalog.product_quality_score",
    "catalog.brand_logo",
    "catalog.prohibited_product",
    "llm.image_output_safety",
}
TEXT_CLASSIFY_TYPES = {
    "text.classify",
    "moderation.prompt_safety",
    "moderation.text",
    "moderation.profanity",
    "moderation.spam_comment",
    "review.fake_detection",
    "review.sentiment",
    "review.topic_tagging",
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
}
FLEX_TYPES = {
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

REF = {
    "ocr": "TaskResourceEnvelope/document-ocr@1.0.0",
    "extract": "TaskResourceEnvelope/document-extract@1.0.0",
    "summarize": "TaskResourceEnvelope/text-summarize@1.0.0",
    "text": "TaskResourceEnvelope/text-classify@1.0.0",
    "vision": "TaskResourceEnvelope/vision-analyze@1.0.0",
    "segment": "TaskResourceEnvelope/image-segmentation@1.0.0",
    "flex": "TaskResourceEnvelope/flex-input@1.0.0",
}

for task in OCR_TYPES:
    ENVELOPE_BY_TASK[task] = REF["ocr"]
for task in EXTRACT_TYPES:
    ENVELOPE_BY_TASK[task] = REF["extract"]
for task in SUMMARIZE_TYPES:
    ENVELOPE_BY_TASK[task] = REF["summarize"]
for task in TEXT_CLASSIFY_TYPES:
    ENVELOPE_BY_TASK[task] = REF["text"]
for task in FLEX_TYPES:
    ENVELOPE_BY_TASK[task] = REF["flex"]
for task in VISION_TYPES:
    if task == "image.remove_background":
        ENVELOPE_BY_TASK[task] = REF["segment"]
    else:
        ENVELOPE_BY_TASK[task] = REF["vision"]


def envelope_ref(task_type: str) -> str:
    if task_type in ENVELOPE_BY_TASK:
        return ENVELOPE_BY_TASK[task_type]
    raise KeyError(f"missing envelope mapping for {task_type}")


def main() -> None:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    bindings: list[dict[str, str]] = []
    for category in catalog["categories"]:
        for item in category["types"]:
            task_type = str(item["value"])
            ref = envelope_ref(task_type)
            item["resourceEnvelopeRef"] = ref
            bindings.append({"taskType": task_type, "resourceEnvelopeRef": ref})

    if len(bindings) != 56:
        raise SystemExit(f"expected 56 bindings, got {len(bindings)}")

    CATALOG.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    BINDINGS_OUT.write_text(
        json.dumps(
            {
                "boundAt": "2026-09-01",
                "total": len(bindings),
                "templateRefs": sorted(set(b["resourceEnvelopeRef"] for b in bindings)),
                "bindings": bindings,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(json.dumps({"status": "ok", "bound": len(bindings)}, indent=2))


if __name__ == "__main__":
    main()
