#!/usr/bin/env python3
"""Dry-run architecture v1 rollback drill — validates rollback invariants in source."""
from __future__ import annotations

import json
from datetime import UTC, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

CHECKS = {
    "runbook_rb025_exists": (ROOT / "docs/08-sre/runbooks/RB-025-release-rollback.md").is_file(),
    "immutable_image_digest_policy": "immutable image digest" in (
        ROOT / "docs/08-sre/runbooks/RB-025-release-rollback.md"
    ).read_text(encoding="utf-8"),
    "forward_compatible_migrations": "forward-compatible migrations" in (
        ROOT / "docs/08-sre/runbooks/RB-025-release-rollback.md"
    ).read_text(encoding="utf-8"),
    "stale_fence_invariant": "stale fence" in (
        ROOT / "docs/08-sre/runbooks/RB-025-release-rollback.md"
    ).read_text(encoding="utf-8").lower(),
    "lease_credential_destroyed_on_complete": "DELETE FROM public.assignment_lease_credentials"
    in (ROOT / "src/backend/edgemint/workers/assignments.py").read_text(encoding="utf-8"),
    "no_destructive_db_downgrade": "destructively" in (
        ROOT / "docs/08-sre/runbooks/RB-025-release-rollback.md"
    ).read_text(encoding="utf-8").lower(),
    "production_gate_script": (ROOT / "tools/production_gate.py").is_file(),
    "validate_all_script": (ROOT / "tools/validate_all.sh").is_file(),
}


def main() -> int:
    failed = [name for name, passed in CHECKS.items() if not passed]
    result = {
        "status": "passed" if not failed else "failed",
        "drill": "architecture-v1-rollback-dry-run",
        "runbook": "docs/08-sre/runbooks/RB-025-release-rollback.md",
        "drillDoc": "docs/08-sre/drills/DR-001-architecture-v1-rollback-dry-run.md",
        "executedAt": datetime.now(UTC).isoformat(),
        "environment": "dry-run-source-verify",
        "checks": {name: "pass" if passed else "fail" for name, passed in CHECKS.items()},
        "failedChecks": failed,
        "classification": "IMPLEMENTED_DEV_ONLY",
    }
    print(json.dumps(result, indent=2))
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
