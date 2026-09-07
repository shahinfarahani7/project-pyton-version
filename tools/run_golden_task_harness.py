#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src" / "backend"))

from edgemint.golden.harness import list_fixture_task_types, run_all_fixtures, run_golden_task


def main() -> int:
    parser = argparse.ArgumentParser(description="Run EdgeMint golden task I/O harness")
    parser.add_argument("--task-type", help="Run a single catalog task type fixture")
    parser.add_argument(
        "--artifact",
        default="plan/evidence/phase-05-p5-cross-04-golden-harness-sample.json",
        help="Write JSON artifact report",
    )
    args = parser.parse_args()

    if args.task_type:
        outcomes = [run_golden_task(args.task_type, root=ROOT)]
    else:
        outcomes = run_all_fixtures(root=ROOT)

    report = {
        "status": "passed" if outcomes and all(item.passed for item in outcomes) else "failed",
        "test": "golden-task-harness",
        "fixtureTaskTypes": list_fixture_task_types(root=ROOT),
        "caseCount": len(outcomes),
        "passed": sum(1 for item in outcomes if item.passed),
        "failed": sum(1 for item in outcomes if not item.passed),
        "results": [item.as_dict() for item in outcomes],
    }
    artifact_path = ROOT / args.artifact
    artifact_path.parent.mkdir(parents=True, exist_ok=True)
    artifact_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: report[key] for key in ("status", "caseCount", "passed", "failed")}, indent=2))
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
