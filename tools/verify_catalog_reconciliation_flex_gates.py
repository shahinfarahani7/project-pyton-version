#!/usr/bin/env python3
"""Verify catalog reconciliation and Flex dispatch gates for P8-A15 / T15."""

from __future__ import annotations

import json
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _git_sha() -> str:
    try:
        return (
            subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True)
            .strip()
        )
    except Exception:
        return "unknown"


def main() -> int:
    errors: list[str] = []
    artifacts = {
        "catalogJson": ROOT / "src/shared/task-types/catalog.json",
        "catalogClosure": ROOT / "src/backend/edgemint/tasks/catalog_closure.py",
        "catalogReconciliation": ROOT / "src/backend/edgemint/tasks/catalog_reconciliation.py",
        "flexEnvelopeDsl": ROOT / "dsl/catalog/resource-envelopes/flex-input.yaml",
        "workerFlexContracts": ROOT / "src/apps/worker/lib/contracts/task_contract_catalog.dart",
        "catalogClosureValidator": ROOT / "tools/validate_catalog_closure.py",
        "catalogInfraVerifier": ROOT / "tools/verify_task_catalog_infrastructure.py",
        "backendTests": ROOT / "src/backend/tests/tasks/test_catalog_reconciliation.py",
        "p5Gap08Evidence": ROOT / "plan/evidence/phase-05-p5-gap-08-catalog-signoff.json",
    }
    for label, path in artifacts.items():
        if not path.is_file():
            errors.append(f"missing artifact ({label}): {path.relative_to(ROOT)}")

    reconciliation = subprocess.run(
        [
            sys.executable,
            "-c",
            "from edgemint.tasks.catalog_reconciliation import build_catalog_reconciliation_snapshot, snapshot_to_dict; "
            "import json; print(json.dumps(snapshot_to_dict(build_catalog_reconciliation_snapshot())))",
        ],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    snapshot: dict[str, object] = {}
    if reconciliation.returncode != 0:
        errors.append("catalog reconciliation snapshot failed")
        errors.append(reconciliation.stderr[-1500:])
    else:
        snapshot = json.loads(reconciliation.stdout)

    if snapshot.get("duplicateCatalogIds"):
        errors.append(f"duplicate catalog IDs: {snapshot['duplicateCatalogIds']}")
    if snapshot.get("duplicateDslCodes"):
        errors.append(f"duplicate DSL codes: {snapshot['duplicateDslCodes']}")
    if snapshot.get("unmappedCatalogIds"):
        errors.append(f"catalog IDs missing DSL: {snapshot['unmappedCatalogIds']}")
    if snapshot.get("reconciledWithHistorical") is not True:
        errors.append(
            f"catalog not reconciled with historical 56: delta={snapshot.get('reconciliationDelta')}"
        )
    if snapshot.get("flexBlockedIds"):
        errors.append(f"flex tasks blocked unexpectedly: {snapshot['flexBlockedIds']}")

    flex_contracts = (
        artifacts["workerFlexContracts"].read_text(encoding="utf-8")
        if artifacts["workerFlexContracts"].is_file()
        else ""
    )
    if "static const flexTypes" not in flex_contracts:
        errors.append("worker flexTypes registry missing")

    backend_test = subprocess.run(
        [sys.executable, "-m", "pytest", str(artifacts["backendTests"]), "-q"],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    backend_passed = backend_test.returncode == 0
    if not backend_passed:
        errors.append("backend pytest failed for catalog reconciliation")
        errors.append(backend_test.stdout[-1500:])
        errors.append(backend_test.stderr[-1500:])

    closure = subprocess.run(
        [sys.executable, str(artifacts["catalogClosureValidator"])],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    closure_passed = closure.returncode == 0
    if not closure_passed:
        errors.append("validate_catalog_closure failed")
        if closure.stdout.strip():
            errors.append(closure.stdout[-1000:])

    evidence = {
        "status": "passed" if not errors else "failed",
        "taskId": "P8-A15",
        "auditId": "A15",
        "acceptanceCase": "T15",
        "architectureVersion": "2.0",
        "sourceSections": ["55", "56", "57", "58", "59", "65", "75"],
        "generatedAt": datetime.now(UTC).isoformat(),
        "commitSha": _git_sha(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "artifacts": {
            k: str(v.relative_to(ROOT)).replace("\\", "/") for k, v in artifacts.items()
        },
        "catalogSnapshot": snapshot,
        "t15Scenario": {
            "title": "Catalog overlap/duplicate IDs; snapshot total differs; Flex contract absent",
            "uniqueIdsReconciledTo56": snapshot.get("reconciledWithHistorical"),
            "noDuplicateIds": not snapshot.get("duplicateCatalogIds")
            and not snapshot.get("duplicateDslCodes"),
            "flexDispatchGate": len(snapshot.get("flexBlockedIds", [])) == 0,
            "catalogClosureSync": closure_passed,
            "integrationHarness": "NOT_RUN",
        },
        "gaps": [
            "T15 intentional duplicate-ID negative injection harness NOT_RUN",
            "Cross-repo catalog export diff automation NOT_RUN",
        ],
        "errors": errors,
    }

    out_path = ROOT / "plan/evidence/phase-08-p8-a15-catalog-reconciliation-flex-gates.json"
    out_path.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence, indent=2))
    return 0 if evidence["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
