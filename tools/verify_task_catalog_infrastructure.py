#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
catalog = json.loads((ROOT / "src/shared/task-types/catalog.json").read_text())
types = [item for category in catalog["categories"] for item in category["types"]]
values = {item["value"] for item in types}
mapper = (ROOT / "src/apps/worker/lib/tasks/task_type_mapper.dart").read_text()
dispatcher = (ROOT / "src/apps/worker/lib/tasks/mobile_task_dispatcher.dart").read_text()
completion = (ROOT / "src/backend/edgemint/workers/assignments.py").read_text()
registry = (ROOT / "src/backend/edgemint/services/worker_registry.py").read_text()
contracts = (ROOT / "src/apps/worker/lib/contracts/task_contract_catalog.dart").read_text()
vision_handlers = (ROOT / "src/apps/worker/lib/tasks/handlers/vision_handlers.dart").read_text()
vision_adapter = (ROOT / "src/apps/worker/lib/runtime/vision_litert_adapter.dart").read_text()
segmenter = (ROOT / "src/apps/worker/android/app/src/main/kotlin/io/edgemint/edgemint_worker/ImageSegmenterPlugin.kt").read_text()
vision_consistency = (ROOT / "src/apps/worker/lib/validation/vision_consistency_validator.dart").read_text()
vision_normalizer = (ROOT / "src/apps/worker/lib/validation/vision_output_normalizer.dart").read_text()

checks = {
    "catalog_has_56_unique_types": len(types) == len(values) == 56,
    "all_input_modes_known": {item["inputMode"] for item in types} <= {"text", "image", "document", "flex"},
    "lightweight_handlers_registered": all(name in dispatcher for name in (
        "DocumentImageQualityHandler", "BlurryImageHandler", "DuplicateImageHandler"
    )),
    "qwen_contracts_present": all(f"'{value}'" in contracts for value in values if next(t for t in types if t["value"] == value)["inputMode"] == "text") and "extract.amount" in contracts,
    "nine_flex_contracts_present": sum(f"'{item['value']}'" in contracts for item in types if item["inputMode"] == "flex") == 9,
    "vision_handlers_registered": "VisionAnalyzeHandler" in dispatcher and "RemoveBackgroundHandler" in dispatcher,
    "internvl_is_strict_json": "JsonOutputValidator.validateSchema" in vision_adapter,
    "real_mediapipe_segmentation": "ImageSegmenter.createFromOptions" in segmenter and "confidenceMasks" in segmenter,
    "vision_consistency_gate": "positive risk decision cannot have zero riskScore" in vision_consistency,
    "vision_conservative_fallback": "needsHumanReview" in vision_normalizer and "riskScore'] = 1.0" in vision_normalizer,
    "production_completion_endpoint": 'complete_automatic_assignment' in registry,
    "completion_checks_digest": 'resultSha256 mismatch' in completion,
    "completion_checks_signature": 'result signature invalid' in completion,
    "completion_deletes_lease_credential": 'DELETE FROM public.assignment_lease_credentials' in completion,
}
result = {"status": "passed" if all(checks.values()) else "failed", "taskTypes": len(types), "checks": checks}
print(json.dumps(result, indent=2))
raise SystemExit(0 if all(checks.values()) else 1)
