#!/usr/bin/env python3
"""Validate disaster-recovery drill evidence for WP-230."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

REQUIRED_FILES = (
    "summary.json",
    "backup-restore.json",
    "cross-region-copy.json",
    "dependency-reconfiguration.json",
    "dns-failover.json",
    "reconciliation-post-restore.json",
    "game-day-communication.json",
    "return-to-primary.json",
)

REQUIRED_EXTERNAL_INPUTS = (
    "STAGING_AWS_ACCOUNT_ID",
    "DR_DRILL_WINDOW",
    "BACKUP_RESTORE_TARGET",
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence_dir", nargs="?", default="evidence/actual/dr")
    args = parser.parse_args()

    dr_dir = Path(args.evidence_dir)
    if not dr_dir.is_absolute():
        dr_dir = ROOT / dr_dir

    errors: list[str] = []
    if not dr_dir.is_dir():
        errors.append(f"DR evidence directory missing: {dr_dir}")

    external_root = ROOT / "evidence" / "actual" / "external-inputs"
    for name in REQUIRED_EXTERNAL_INPUTS:
        if not (external_root / f"{name}.json").is_file():
            errors.append(f"missing external input: {name}")

    for name in REQUIRED_FILES:
        if not (dr_dir / name).is_file():
            errors.append(f"missing DR evidence: {name}")

    if errors:
        print(json.dumps({"status": "failed", "errors": errors}, indent=2))
        return 1

    summary = json.loads((dr_dir / "summary.json").read_text(encoding="utf-8"))
    backup = json.loads((dr_dir / "backup-restore.json").read_text(encoding="utf-8"))
    reconciliation = json.loads((dr_dir / "reconciliation-post-restore.json").read_text(encoding="utf-8"))
    game_day = json.loads((dr_dir / "game-day-communication.json").read_text(encoding="utf-8"))

    if summary.get("status") != "passed":
        errors.append("DR summary status is not passed")
    if summary.get("measuredRpoSeconds", 9999) > summary.get("rpoTargetSeconds", 300):
        errors.append("measured RPO exceeds 5 minute target")
    if summary.get("measuredRtoSeconds", 9999) > summary.get("rtoTargetSeconds", 3600):
        errors.append("measured RTO exceeds 60 minute target")
    if not backup.get("integrityVerified"):
        errors.append("backup restore integrity not verified")
    if not backup.get("rlsPoliciesVerified"):
        errors.append("RLS policies not verified after restore")
    if not backup.get("ledgerCheckpointVerified"):
        errors.append("ledger checkpoint not verified after restore")
    if not backup.get("eventCheckpointVerified"):
        errors.append("event checkpoint not verified after restore")
    if reconciliation.get("ledgerDriftMicros", 1) != 0:
        errors.append("ledger drift detected after restore")
    if not game_day.get("executedWithoutAuthorAssistance"):
        errors.append("game day not executable without author assistance")

    result = {
        "status": "passed" if not errors else "failed",
        "drDir": str(dr_dir.relative_to(ROOT)),
        "measuredRpoSeconds": summary.get("measuredRpoSeconds"),
        "measuredRtoSeconds": summary.get("measuredRtoSeconds"),
        "errors": errors,
    }
    print(json.dumps(result, indent=2))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
