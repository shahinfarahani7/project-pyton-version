#!/usr/bin/env python3
"""Evaluate capacity and unit-economics evidence under WP-210 acceptance thresholds."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CAPACITY_DIR = ROOT / "evidence" / "actual" / "capacity"

REQUIRED_FILES = (
    "summary.json",
    "load-profile.json",
    "soak-72h.json",
    "stress-profile.json",
    "margin-stressed.json",
    "hot-key-test.json",
    "worker-fleet-simulation.json",
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence_dir", nargs="?", default="evidence/actual")
    args = parser.parse_args()
    evidence_root = Path(args.evidence_dir)
    if not evidence_root.is_absolute():
        evidence_root = ROOT / evidence_root
    capacity_dir = evidence_root / "capacity"

    errors: list[str] = []
    for name in REQUIRED_FILES:
        if not (capacity_dir / name).is_file():
            errors.append(f"missing capacity evidence: {name}")

    if errors:
        print(json.dumps({"status": "failed", "errors": errors}, indent=2))
        return 1

    load = json.loads((capacity_dir / "load-profile.json").read_text(encoding="utf-8"))
    soak = json.loads((capacity_dir / "soak-72h.json").read_text(encoding="utf-8"))
    stress = json.loads((capacity_dir / "stress-profile.json").read_text(encoding="utf-8"))
    margin = json.loads((capacity_dir / "margin-stressed.json").read_text(encoding="utf-8"))
    fleet = json.loads((capacity_dir / "worker-fleet-simulation.json").read_text(encoding="utf-8"))
    summary = json.loads((capacity_dir / "summary.json").read_text(encoding="utf-8"))

    if load.get("admissionP95Ms", 9999) > 500:
        errors.append("load profile admission p95 exceeds 500ms")
    if load.get("heartbeatP95Ms", 9999) > 250:
        errors.append("load profile heartbeat p95 exceeds 250ms")
    if soak.get("queueUnbounded"):
        errors.append("soak detected unbounded queue")
    if soak.get("memoryLeakDetected"):
        errors.append("soak detected memory leak")
    if soak.get("reconciliationDriftMicros", 1) != 0:
        errors.append("soak reconciliation drift detected")
    if soak.get("thermalBreaches", 1) > 0:
        errors.append("soak thermal policy breach")
    if stress.get("peakInFlight", 9999) > fleet.get("inFlightLimit", 256):
        errors.append("stress exceeded in-flight backpressure limit")
    if margin.get("stressedContributionMarginBps", 0) < margin.get("minimumRequiredBps", 1500):
        errors.append("stressed contribution margin below 15%")
    if summary.get("status") != "passed":
        errors.append("capacity summary not passed")

    result = {
        "status": "passed" if not errors else "failed",
        "capacityDir": str(capacity_dir.relative_to(ROOT)),
        "admissionP95Ms": load.get("admissionP95Ms"),
        "heartbeatP95Ms": load.get("heartbeatP95Ms"),
        "stressedContributionMarginBps": margin.get("stressedContributionMarginBps"),
        "errors": errors,
    }
    print(json.dumps(result, indent=2))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
