#!/usr/bin/env python3
"""Generate TaskType DSL + golden fixtures for the 14 Phase 5 vision closure tasks."""
from __future__ import annotations

import json
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
DSL = ROOT / "dsl/catalog/task-types"
FIX = ROOT / "tests/golden/fixtures"

VISION_TASKS: list[dict[str, object]] = [
    {
        "code": "image.classify",
        "file": "image-classify.yaml",
        "vision_category": "vlm",
        "data_required": ["label", "confidence", "evidence"],
        "data_props": {
            "label": {"type": "string"},
            "confidence": {"type": "number", "minimum": 0, "maximum": 1},
            "evidence": {"type": "array", "items": {"type": "string"}},
        },
        "golden_data": {"label": "product", "confidence": 0.91, "evidence": ["box shape", "label text"]},
    },
    {
        "code": "safety.nsfw_detection",
        "file": "safety-nsfw-detection.yaml",
        "vision_category": "safety",
        "data_required": ["nsfw", "riskScore", "categories", "reason"],
        "data_props": {
            "nsfw": {"type": "boolean"},
            "riskScore": {"type": "number", "minimum": 0, "maximum": 1},
            "categories": {"type": "array", "items": {"type": "string"}},
            "reason": {"type": "string"},
        },
        "golden_data": {"nsfw": False, "riskScore": 0.06, "categories": [], "reason": "No adult content detected."},
    },
    {
        "code": "safety.violence_detection",
        "file": "safety-violence-detection.yaml",
        "vision_category": "safety",
        "data_required": ["violence", "riskScore", "categories", "reason"],
        "data_props": {
            "violence": {"type": "boolean"},
            "riskScore": {"type": "number", "minimum": 0, "maximum": 1},
            "categories": {"type": "array", "items": {"type": "string"}},
            "reason": {"type": "string"},
        },
        "golden_data": {"violence": False, "riskScore": 0.04, "categories": [], "reason": "No violence detected."},
    },
    {
        "code": "safety.weapon_detection",
        "file": "safety-weapon-detection.yaml",
        "vision_category": "safety",
        "data_required": ["weapon", "riskScore", "types", "reason"],
        "data_props": {
            "weapon": {"type": "boolean"},
            "riskScore": {"type": "number", "minimum": 0, "maximum": 1},
            "types": {"type": "array", "items": {"type": "string"}},
            "reason": {"type": "string"},
        },
        "golden_data": {"weapon": False, "riskScore": 0.03, "types": [], "reason": "No weapons visible."},
    },
    {
        "code": "safety.unsafe_image",
        "file": "safety-unsafe-image.yaml",
        "vision_category": "safety",
        "data_required": ["safe", "riskScore", "categories", "reason"],
        "data_props": {
            "safe": {"type": "boolean"},
            "riskScore": {"type": "number", "minimum": 0, "maximum": 1},
            "categories": {"type": "array", "items": {"type": "string"}},
            "reason": {"type": "string"},
        },
        "golden_data": {"safe": True, "riskScore": 0.05, "categories": [], "reason": "Image appears safe."},
    },
    {
        "code": "moderation.profile_image",
        "file": "moderation-profile-image.yaml",
        "vision_category": "safety",
        "data_required": ["allowed", "riskScore", "issues", "reason"],
        "data_props": {
            "allowed": {"type": "boolean"},
            "riskScore": {"type": "number", "minimum": 0, "maximum": 1},
            "issues": {"type": "array", "items": {"type": "string"}},
            "reason": {"type": "string"},
        },
        "golden_data": {"allowed": True, "riskScore": 0.08, "issues": [], "reason": "Profile image is suitable."},
    },
    {
        "code": "moderation.generated_image",
        "file": "moderation-generated-image.yaml",
        "vision_category": "safety",
        "data_required": ["allowed", "riskScore", "categories", "reason"],
        "data_props": {
            "allowed": {"type": "boolean"},
            "riskScore": {"type": "number", "minimum": 0, "maximum": 1},
            "categories": {"type": "array", "items": {"type": "string"}},
            "reason": {"type": "string"},
        },
        "golden_data": {"allowed": True, "riskScore": 0.07, "categories": [], "reason": "Generated image passes policy."},
    },
    {
        "code": "catalog.image_tagging",
        "file": "catalog-image-tagging.yaml",
        "vision_category": "catalog",
        "data_required": ["tags", "confidence", "evidence"],
        "data_props": {
            "tags": {"type": "array", "items": {"type": "string"}},
            "confidence": {"type": "number", "minimum": 0, "maximum": 1},
            "evidence": {"type": "array", "items": {"type": "string"}},
        },
        "golden_data": {"tags": ["red", "sneaker", "studio"], "confidence": 0.89, "evidence": ["red upper", "white sole"]},
    },
    {
        "code": "catalog.product_classification",
        "file": "catalog-product-classification.yaml",
        "vision_category": "catalog",
        "data_required": ["category", "confidence", "alternatives"],
        "data_props": {
            "category": {"type": "string"},
            "confidence": {"type": "number", "minimum": 0, "maximum": 1},
            "alternatives": {"type": "array", "items": {"type": "string"}},
        },
        "golden_data": {"category": "footwear", "confidence": 0.92, "alternatives": ["apparel"]},
    },
    {
        "code": "catalog.product_quality_score",
        "file": "catalog-product-quality-score.yaml",
        "vision_category": "catalog",
        "data_required": ["score", "issues", "recommendations"],
        "data_props": {
            "score": {"type": "number", "minimum": 0, "maximum": 1},
            "issues": {"type": "array", "items": {"type": "string"}},
            "recommendations": {"type": "array", "items": {"type": "string"}},
        },
        "golden_data": {"score": 0.84, "issues": ["slight glare"], "recommendations": ["retake with softer lighting"]},
    },
    {
        "code": "catalog.brand_logo",
        "file": "catalog-brand-logo.yaml",
        "vision_category": "catalog",
        "data_required": ["detected", "brands", "confidence", "evidence"],
        "data_props": {
            "detected": {"type": "boolean"},
            "brands": {"type": "array", "items": {"type": "string"}},
            "confidence": {"type": "number", "minimum": 0, "maximum": 1},
            "evidence": {"type": "array", "items": {"type": "string"}},
        },
        "golden_data": {"detected": True, "brands": ["ACME"], "confidence": 0.87, "evidence": ["logo on packaging"]},
    },
    {
        "code": "catalog.prohibited_product",
        "file": "catalog-prohibited-product.yaml",
        "vision_category": "catalog",
        "data_required": ["prohibited", "riskScore", "categories", "reason"],
        "data_props": {
            "prohibited": {"type": "boolean"},
            "riskScore": {"type": "number", "minimum": 0, "maximum": 1},
            "categories": {"type": "array", "items": {"type": "string"}},
            "reason": {"type": "string"},
        },
        "golden_data": {"prohibited": False, "riskScore": 0.1, "categories": [], "reason": "No prohibited product detected."},
    },
    {
        "code": "llm.image_output_safety",
        "file": "llm-image-output-safety.yaml",
        "vision_category": "safety",
        "data_required": ["safe", "riskScore", "categories", "reason"],
        "data_props": {
            "safe": {"type": "boolean"},
            "riskScore": {"type": "number", "minimum": 0, "maximum": 1},
            "categories": {"type": "array", "items": {"type": "string"}},
            "reason": {"type": "string"},
        },
        "golden_data": {"safe": True, "riskScore": 0.05, "categories": [], "reason": "Generated output is policy compliant."},
    },
    {
        "code": "image.remove_background",
        "file": "image-remove-background.yaml",
        "vision_category": "segmentation",
        "data_required": ["mimeType", "imageBase64", "sizeBytes", "segmentationModel"],
        "data_props": {
            "mimeType": {"type": "string"},
            "imageBase64": {"type": "string"},
            "sizeBytes": {"type": "integer", "minimum": 1},
            "segmentationModel": {"type": "string"},
        },
        "golden_data": {
            "mimeType": "image/png",
            "imageBase64": "iVBORw0KGgo=",
            "sizeBytes": 128,
            "segmentationModel": "MediaPipe SelfieSegmenter float16",
        },
        "flat_output": True,
    },
]


def dsl_doc(task: dict[str, object]) -> dict[str, object]:
    code = str(task["code"])
    return {
        "apiVersion": "edgemint.io/v1",
        "kind": "TaskType",
        "metadata": {
            "name": str(task["file"]).replace(".yaml", ""),
            "version": "2.0.0",
            "status": "active",
            "description": f"Production vision contract for {code}",
            "labels": {"domain": "vision", "family": "internvl", "visionCategory": str(task["vision_category"])},
            "owners": ["product", "platform"],
        },
        "spec": {
            "code": code,
            "lifecycle": "commercial-candidate",
            "billing": {"measure": "image", "quantum": 1, "rounding": "ceil", "minimumQuanta": 1},
            "inputSchema": {
                "type": "object",
                "required": ["assetRef"],
                "additionalProperties": False,
                "properties": {
                    "assetRef": {"type": "string", "pattern": "^file_[A-Za-z0-9]+$"},
                    "options": {"type": "object"},
                },
            },
            "outputSchema": {
                "type": "object",
                "required": ["status", "data", "metrics"],
                "additionalProperties": False,
                "properties": {
                    "status": {"enum": ["succeeded", "partial", "failed"]},
                    "data": {
                        "type": "object",
                        "required": task["data_required"],
                        "properties": task["data_props"],
                    },
                    "metrics": {"type": "object"},
                },
            },
            "inputLimits": {
                "maximumBytes": 20971520,
                "allowedContentTypes": ["image/jpeg", "image/png", "image/webp"],
            },
            "requiredCapabilities": {
                "minimumWorkerTier": "T2",
                "attestationRequired": True,
                "secureNetworkRequired": True,
                "maximumExecutionSeconds": 180,
            },
            "modelCandidates": [{"modelRef": "ModelProfile/minicpm-v-4.6-q4@2.0.0", "priority": 1}],
            "verificationPolicyRef": "VerificationPolicy/default-verification-v2@2.0.0",
            "dataPolicyRef": "DataPolicy/confidential-v2@2.0.0",
            "defaultVerification": "standard",
            "retention": {"inputHours": 24, "resultDays": 30, "workerTemporaryMinutes": 15},
            "idempotencyScope": "workspace+operation+key",
            "editableAfterSubmit": False,
            "safety": {"contentPolicy": "customer-acceptable-use-v1", "humanReviewAllowed": True},
        },
    }


def main() -> int:
    for task in VISION_TASKS:
        code = str(task["code"])
        (DSL / str(task["file"])).write_text(
            yaml.safe_dump(dsl_doc(task), sort_keys=False, allow_unicode=True),
            encoding="utf-8",
        )
        if task.get("flat_output"):
            worker_output = dict(task["golden_data"])  # type: ignore[arg-type]
        else:
            worker_output = {
                "data": task["golden_data"],
                "visionRuntimeClass": str(task["vision_category"]) + "_runtime",
            }
        fixture = {
            "taskType": code,
            "fixtureVersion": "1",
            "description": f"Reference golden I/O for {code}",
            "input": {"assetRef": "file_golden_vision_001", "options": {}},
            "workerResult": {
                "schemaVersion": "1",
                "taskId": f"tsk_golden_{code.replace('.', '_')}",
                "status": "SUCCEEDED",
                "output": worker_output,
                "metrics": {"llmMs": 900, "visionMs": 900},
            },
            "minimumConfidenceMilli": 960,
        }
        (FIX / f"{code}.json").write_text(json.dumps(fixture, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"generated": len(VISION_TASKS)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
