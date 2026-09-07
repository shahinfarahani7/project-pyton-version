#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src" / "backend"))

from edgemint.routing.retry_policy_matrix import RetryPolicyMatrix, catalog_task_types


def main() -> int:
    matrix = RetryPolicyMatrix.load(root=ROOT)
    catalog = catalog_task_types(root=ROOT)
    flex_blocked = [
        task_type
        for task_type, policy in matrix.entries.items()
        if not policy.executable
    ]
    artifact = {
        "status": "passed" if len(matrix.entries) == len(catalog) == 56 else "failed",
        "test": "retry-policy-matrix-export",
        "catalogTaskCount": len(catalog),
        "matrixEntryCount": len(matrix.entries),
        "flexNonExecutableCount": len(flex_blocked),
        "flexNonExecutable": sorted(flex_blocked),
        "entries": {
            task_type: {
                "retryClass": policy.retry_class.value,
                "qualityFailureRetryClass": policy.quality_failure_retry_class.value,
                "executable": policy.executable,
                "maxAutomaticRetries": policy.max_automatic_retries,
            }
            for task_type, policy in sorted(matrix.entries.items())
        },
    }
    out_path = ROOT / "plan" / "evidence" / "phase-05-p5-cross-02-retry-policy-matrix.json"
    out_path.write_text(json.dumps(artifact, indent=2), encoding="utf-8")
    print(json.dumps({"status": artifact["status"], "path": str(out_path.relative_to(ROOT))}, indent=2))
    return 0 if artifact["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
