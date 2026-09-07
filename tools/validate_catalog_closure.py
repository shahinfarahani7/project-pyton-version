#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src" / "backend"))

from edgemint.tasks.catalog_closure import validate_catalog_sync


def main() -> int:
    reports = validate_catalog_sync()
    incomplete_metadata = [report for report in reports if report.executable and not report.metadata_complete]
    non_executable = [report for report in reports if not report.executable]
    dsl_complete = [report.task_type for report in reports if report.dsl_contract_complete]
    contract_incomplete = [
        report.task_type
        for report in reports
        if report.executable and not report.contract_complete
    ]
    artifact = {
        "status": "passed"
        if not incomplete_metadata and not contract_incomplete and len(reports) == 56
        else "failed",
        "test": "catalog-closure-sync",
        "catalogTaskCount": len(reports),
        "executableCount": sum(1 for report in reports if report.executable),
        "nonExecutableCount": len(non_executable),
        "metadataIncompleteCount": len(incomplete_metadata),
        "dslContractCompleteCount": len(dsl_complete),
        "goldenFixtureCount": sum(1 for report in reports if report.golden_fixture_present),
        "contractCompleteCount": sum(1 for report in reports if report.contract_complete),
        "contractIncompleteTaskTypes": sorted(contract_incomplete),
        "nonExecutableTaskTypes": sorted(report.task_type for report in non_executable),
        "metadataIncomplete": [
            {"taskType": report.task_type, "missingFields": list(report.missing_fields)}
            for report in incomplete_metadata
        ],
    }
    out_path = ROOT / "plan" / "evidence" / "phase-05-p5-cross-05-catalog-closure-sync.json"
    out_path.write_text(json.dumps(artifact, indent=2) + "\n", encoding="utf-8")
    signoff_path = ROOT / "plan" / "evidence" / "phase-05-p5-gap-08-catalog-signoff.json"
    signoff_path.write_text(json.dumps(artifact, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: artifact[key] for key in ("status", "catalogTaskCount", "contractCompleteCount")}, indent=2))
    return 0 if artifact["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
