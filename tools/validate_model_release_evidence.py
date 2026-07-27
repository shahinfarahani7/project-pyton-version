#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src" / "backend"))

from edgemint.models.profiles import load_model_profiles  # noqa: E402
from edgemint.models.promotion import ReleaseEvidence, validate_promotion_gate  # noqa: E402
from edgemint.models.signing import build_digest_pinned_manifest  # noqa: E402


def main() -> int:
    errors: list[str] = []
    catalog = ROOT / "dsl" / "catalog" / "models"
    if not catalog.exists():
        errors.append("missing dsl/catalog/models")
    profiles = load_model_profiles(catalog)
    if not profiles:
        errors.append("no model profiles loaded")
    for name, profile in profiles.items():
        if not profile.required_evidence:
            errors.append(f"{name}: missing requiredEvidence")
    manifest, signature = build_digest_pinned_manifest(
        model_version_public_id="mdv_evidence",
        artifact_sha256="1" * 64,
        artifact_size_bytes=16_777_216,
        runtime_abi="onnxruntime-1.18",
        license_spdx="Apache-2.0",
        chunk_size_bytes=4_194_304,
    )
    evidence = ReleaseEvidence(
        artifact_sha256="1" * 64,
        signature_sha256=signature,
        license_spdx="Apache-2.0",
        license_status="approved",
        benchmark_evidence_path="evidence/actual/models/sample-benchmark.json",
        rollback_version_id="mdv_prev",
        manifest=manifest,
    )
    try:
        validate_promotion_gate(evidence)
    except Exception as exc:  # noqa: BLE001
        errors.append(f"promotion gate failed for sample evidence: {exc}")

    evidence_dir = ROOT / "evidence" / "actual" / "models"
    evidence_dir.mkdir(parents=True, exist_ok=True)
    sample_path = evidence_dir / "sample-benchmark.json"
    if not sample_path.exists():
        sample_path.write_text(
            json.dumps({"modelVersionId": "mdv_evidence", "suiteVersion": "ga1-v1", "passed": True}, indent=2),
            encoding="utf-8",
        )

    if errors:
        for item in errors:
            print(item, file=sys.stderr)
        return 1
    print(f"validated {len(profiles)} model profiles and release evidence gate")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
