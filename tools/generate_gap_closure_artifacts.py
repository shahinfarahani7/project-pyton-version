#!/usr/bin/env python3
"""Generate TaskType DSL + golden fixtures for Phase 5 catalog gap tasks."""
from __future__ import annotations

import json
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
DSL = ROOT / "dsl/catalog/task-types"
FIX = ROOT / "tests/golden/fixtures"

OCR_OUTPUT_PROPS = {
    "rawText": {"type": "string"},
    "ocrLines": {
        "type": "array",
        "items": {
            "type": "object",
            "properties": {
                "text": {"type": "string"},
                "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                "box": {"type": "array", "items": {"type": "number"}},
            },
        },
    },
}

OCR_GOLDEN_LINE = {
    "text": "TOTAL 42.50 USD",
    "confidence": 0.93,
    "box": [10, 20, 400, 48],
}

OCR_TASKS = [
    ("ocr.receipt", "ocr-receipt.yaml", "receipt", "OCR receipt variant routed to paddle_ocr runtime"),
    ("ocr.invoice", "ocr-invoice.yaml", "invoice", "OCR invoice variant routed to paddle_ocr runtime"),
    ("ocr.simple_form", "ocr-simple-form.yaml", "simple_form", "OCR simple form variant routed to paddle_ocr runtime"),
    ("ocr.product_label", "ocr-product-label.yaml", "product_label", "OCR product label variant routed to paddle_ocr runtime"),
]

QUALITY_TASKS = [
    (
        "quality.document_image",
        "quality-document-image.yaml",
        "document_quality",
        ["score", "brightness", "contrast", "sharpness", "clippedRatio", "acceptable"],
        {
            "score": {"type": "number", "minimum": 0, "maximum": 1},
            "brightness": {"type": "number"},
            "contrast": {"type": "number", "minimum": 0},
            "sharpness": {"type": "number", "minimum": 0},
            "clippedRatio": {"type": "number", "minimum": 0, "maximum": 1},
            "acceptable": {"type": "boolean"},
        },
        {
            "score": 0.78,
            "brightness": 182.0,
            "contrast": 41.2,
            "sharpness": 210.5,
            "clippedRatio": 0.02,
            "acceptable": True,
        },
    ),
    (
        "quality.blurry_image",
        "quality-blurry-image.yaml",
        "blur_detection",
        ["laplacianVariance", "blurry", "threshold"],
        {
            "laplacianVariance": {"type": "number", "minimum": 0},
            "blurry": {"type": "boolean"},
            "threshold": {"type": "number", "minimum": 0},
        },
        {"laplacianVariance": 245.6, "blurry": False, "threshold": 100},
    ),
]


def _ocr_dsl(code: str, file_name: str, variant: str, description: str) -> dict[str, object]:
    return {
        "apiVersion": "edgemint.io/v1",
        "kind": "TaskType",
        "metadata": {
            "name": file_name.replace(".yaml", ""),
            "version": "2.0.0",
            "status": "active",
            "description": description,
            "labels": {"domain": "ocr", "family": "paddle_ocr", "ocrVariant": variant, "runtimeClass": "paddle_ocr"},
            "owners": ["product", "platform"],
        },
        "spec": {
            "code": code,
            "lifecycle": "commercial-candidate",
            "billing": {"measure": "page", "quantum": 1, "rounding": "ceil", "minimumQuanta": 1},
            "inputSchema": {
                "type": "object",
                "required": ["assetRef", "options"],
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
                    "data": {"type": "object", "properties": OCR_OUTPUT_PROPS},
                    "metrics": {"type": "object"},
                },
            },
            "inputLimits": {
                "maximumBytes": 52428800,
                "allowedContentTypes": ["application/pdf", "image/jpeg", "image/png"],
            },
            "requiredCapabilities": {
                "minimumWorkerTier": "T1",
                "attestationRequired": True,
                "secureNetworkRequired": True,
                "maximumExecutionSeconds": 300,
            },
            "modelCandidates": [{"modelRef": "ModelProfile/paddleocr-mobile@2.0.0", "priority": 1}],
            "verificationPolicyRef": "VerificationPolicy/default-verification-v2@2.0.0",
            "dataPolicyRef": "DataPolicy/confidential-v2@2.0.0",
            "defaultVerification": "verified",
            "retention": {"inputHours": 24, "resultDays": 30, "workerTemporaryMinutes": 15},
            "idempotencyScope": "workspace+operation+key",
            "editableAfterSubmit": False,
            "safety": {"contentPolicy": "customer-acceptable-use-v1", "humanReviewAllowed": True},
        },
    }


def _quality_dsl(
    code: str,
    file_name: str,
    category: str,
    required: list[str],
    props: dict[str, object],
    description: str,
) -> dict[str, object]:
    return {
        "apiVersion": "edgemint.io/v1",
        "kind": "TaskType",
        "metadata": {
            "name": file_name.replace(".yaml", ""),
            "version": "2.0.0",
            "status": "active",
            "description": description,
            "labels": {
                "domain": "vision",
                "family": "lightweight",
                "visionCategory": "image_classifier",
                "qualityCategory": category,
                "runtimeClass": "image_classifier",
            },
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
                    "data": {"type": "object", "required": required, "properties": props},
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
                "maximumExecutionSeconds": 60,
            },
            "modelCandidates": [],
            "verificationPolicyRef": "VerificationPolicy/default-verification-v2@2.0.0",
            "dataPolicyRef": "DataPolicy/confidential-v2@2.0.0",
            "defaultVerification": "standard",
            "retention": {"inputHours": 24, "resultDays": 30, "workerTemporaryMinutes": 15},
            "idempotencyScope": "workspace+operation+key",
            "editableAfterSubmit": False,
            "safety": {"contentPolicy": "customer-acceptable-use-v1", "humanReviewAllowed": True},
        },
    }


def _duplicate_dsl() -> dict[str, object]:
    return {
        "apiVersion": "edgemint.io/v1",
        "kind": "TaskType",
        "metadata": {
            "name": "catalog-duplicate-image",
            "version": "2.0.0",
            "status": "active",
            "description": "Duplicate image detection via lightweight dHash similarity",
            "labels": {
                "domain": "vision",
                "family": "lightweight",
                "visionCategory": "embedding",
                "runtimeClass": "embedding_runtime",
            },
            "owners": ["product", "platform"],
        },
        "spec": {
            "code": "catalog.duplicate_image",
            "lifecycle": "commercial-candidate",
            "billing": {"measure": "image", "quantum": 2, "rounding": "ceil", "minimumQuanta": 1},
            "inputSchema": {
                "type": "object",
                "required": ["assetRef", "compareAssetRef"],
                "additionalProperties": False,
                "properties": {
                    "assetRef": {"type": "string", "pattern": "^file_[A-Za-z0-9]+$"},
                    "compareAssetRef": {"type": "string", "pattern": "^file_[A-Za-z0-9]+$"},
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
                        "required": ["hammingDistance", "similarity", "duplicate", "algorithm"],
                        "properties": {
                            "hammingDistance": {"type": "integer", "minimum": 0},
                            "similarity": {"type": "number", "minimum": 0, "maximum": 1},
                            "duplicate": {"type": "boolean"},
                            "algorithm": {"type": "string"},
                        },
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
                "maximumExecutionSeconds": 60,
            },
            "modelCandidates": [],
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
    generated = 0
    for code, file_name, variant, description in OCR_TASKS:
        (DSL / file_name).write_text(
            yaml.safe_dump(_ocr_dsl(code, file_name, variant, description), sort_keys=False, allow_unicode=True),
            encoding="utf-8",
        )
        fixture = {
            "taskType": code,
            "fixtureVersion": "1",
            "description": f"Reference golden I/O for {code}",
            "input": {"assetRef": f"file_golden_{variant}_001", "options": {"language": "en"}},
            "workerResult": {
                "schemaVersion": "1",
                "taskId": f"tsk_golden_{code.replace('.', '_')}",
                "status": "SUCCEEDED",
                "output": {
                    "rawText": "TOTAL 42.50 USD",
                    "ocrLines": [OCR_GOLDEN_LINE],
                },
                "metrics": {"averageOcrConfidence": 0.93, "ocrMs": 980},
            },
            "minimumConfidenceMilli": 960,
        }
        (FIX / f"{code}.json").write_text(json.dumps(fixture, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        generated += 1

    for code, file_name, category, required, props, golden_data in QUALITY_TASKS:
        (DSL / file_name).write_text(
            yaml.safe_dump(
                _quality_dsl(code, file_name, category, required, props, f"Lightweight quality task for {code}"),
                sort_keys=False,
                allow_unicode=True,
            ),
            encoding="utf-8",
        )
        fixture = {
            "taskType": code,
            "fixtureVersion": "1",
            "description": f"Reference golden I/O for {code}",
            "input": {"assetRef": "file_golden_quality_001", "options": {}},
            "workerResult": {
                "schemaVersion": "1",
                "taskId": f"tsk_golden_{code.replace('.', '_')}",
                "status": "SUCCEEDED",
                "output": {
                    "data": golden_data,
                    "visionRuntimeClass": "image_classifier_runtime",
                },
                "metrics": {"visionMs": 120},
            },
            "minimumConfidenceMilli": 960,
        }
        (FIX / f"{code}.json").write_text(json.dumps(fixture, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        generated += 1

    (DSL / "catalog-duplicate-image.yaml").write_text(
        yaml.safe_dump(_duplicate_dsl(), sort_keys=False, allow_unicode=True),
        encoding="utf-8",
    )
    duplicate_fixture = {
        "taskType": "catalog.duplicate_image",
        "fixtureVersion": "1",
        "description": "Reference golden I/O for catalog.duplicate_image",
        "input": {
            "assetRef": "file_golden_dup_primary",
            "compareAssetRef": "file_golden_dup_compare",
            "options": {},
        },
        "workerResult": {
            "schemaVersion": "1",
            "taskId": "tsk_golden_catalog_duplicate_image",
            "status": "SUCCEEDED",
            "output": {
                "data": {
                    "hammingDistance": 3,
                    "similarity": 0.953125,
                    "duplicate": True,
                    "algorithm": "dHash-64",
                },
                "visionRuntimeClass": "embedding_runtime",
            },
            "metrics": {"visionMs": 85},
        },
        "minimumConfidenceMilli": 960,
    }
    (FIX / "catalog.duplicate_image.json").write_text(
        json.dumps(duplicate_fixture, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    generated += 1
    print(json.dumps({"generated": generated}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
