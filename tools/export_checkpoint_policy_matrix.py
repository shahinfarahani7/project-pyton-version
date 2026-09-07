#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src" / "backend"))

from edgemint.routing.checkpoint_policy_matrix import CheckpointPolicyMatrix, catalog_task_types


def main() -> int:
    matrix = CheckpointPolicyMatrix.load(root=ROOT)
    catalog = catalog_task_types(root=ROOT)
    enabled = [task_type for task_type, policy in matrix.entries.items() if policy.checkpoint_enabled]
    artifact = {
        "status": "passed" if len(matrix.entries) == len(catalog) == 56 else "failed",
        "test": "checkpoint-policy-matrix-export",
        "catalogTaskCount": len(catalog),
        "matrixEntryCount": len(matrix.entries),
        "checkpointEnabledCount": len(enabled),
        "checkpointEnabledTaskTypes": sorted(enabled),
        "entries": {
            task_type: {
                "checkpointEnabled": policy.checkpoint_enabled,
                "checkpointStrategy": policy.checkpoint_strategy,
                "maximumIntervalSeconds": policy.maximum_interval_seconds,
            }
            for task_type, policy in sorted(matrix.entries.items())
        },
    }
    out_path = ROOT / "plan" / "evidence" / "phase-05-p5-cross-03-checkpoint-policy-matrix.json"
    out_path.write_text(json.dumps(artifact, indent=2), encoding="utf-8")
    print(json.dumps({"status": artifact["status"], "path": str(out_path.relative_to(ROOT))}, indent=2))
    return 0 if artifact["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
