#!/usr/bin/env python3
"""Verify tenant/data trust and permitted Cloud artifacts for P8-A07 / T07."""

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
        "dataPolicyDsl": ROOT / "dsl/policies/data/production-data-policy-v1.yaml",
        "dataPolicySchema": ROOT / "dsl/schemas/datapolicy.schema.json",
        "dataPolicyRegistry": ROOT / "src/backend/edgemint/security/data_policy_registry.py",
        "tenantDataTrust": ROOT / "src/backend/edgemint/security/tenant_data_trust.py",
        "workspaceDataTrust": ROOT / "src/backend/edgemint/security/workspace_data_trust.py",
        "cloudFallback": ROOT / "src/backend/edgemint/routing/cloud_fallback.py",
        "admissionWiring": ROOT / "src/backend/edgemint/tasks/admission.py",
        "sessionWiring": ROOT / "src/backend/edgemint/workers/sessions.py",
        "sqlBindings": ROOT / "database/sql/031_workspace_data_trust.sql",
        "backendTests": ROOT / "src/backend/tests/security/test_tenant_data_trust.py",
        "cloudFallbackTests": ROOT / "src/backend/tests/routing/test_cloud_fallback.py",
    }
    for label, path in artifacts.items():
        if not path.is_file():
            errors.append(f"missing artifact ({label}): {path.relative_to(ROOT)}")

    policy_yaml = (
        artifacts["dataPolicyDsl"].read_text(encoding="utf-8")
        if artifacts["dataPolicyDsl"].is_file()
        else ""
    )
    for token in (
        "prohibitedDestinations:",
        "cross_tenant_artifact",
        "permittedCloudRegions:",
        "requireDataOwnerProcessingConsent: true",
    ):
        if token not in policy_yaml:
            errors.append(f"data policy DSL missing token: {token}")

    backend_test = subprocess.run(
        [
            sys.executable,
            "-m",
            "pytest",
            str(artifacts["backendTests"]),
            str(artifacts["cloudFallbackTests"]),
            "-q",
        ],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    backend_passed = backend_test.returncode == 0
    if not backend_passed:
        errors.append("backend pytest failed for tenant/cloud trust tests")
        errors.append(backend_test.stdout[-1500:])
        errors.append(backend_test.stderr[-1500:])

    evidence = {
        "status": "passed" if not errors else "failed",
        "taskId": "P8-A07",
        "auditId": "A07",
        "acceptanceCase": "T07",
        "architectureVersion": "2.0",
        "sourceSections": ["10", "17", "52", "61"],
        "generatedAt": datetime.now(UTC).isoformat(),
        "commitSha": _git_sha(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "artifacts": {k: str(v.relative_to(ROOT)).replace("\\", "/") for k, v in artifacts.items()},
        "t07Scenario": {
            "title": "Wrong tenant, revoked credentials, prohibited destination, Cloud threshold",
            "crossTenantArtifactDenied": backend_passed,
            "revokedWorkerDeviceDenied": backend_passed,
            "prohibitedCloudRegionDenied": backend_passed,
            "cloudTimerNeverCreatesPermissionAlone": backend_passed,
            "integrationHarness": "NOT_RUN",
        },
        "gaps": [
            "T07 end-to-end wrong-tenant artifact integration harness NOT_RUN",
            "Workspace data-policy binding seed/migration for production tenants pending",
            "Attestation trust verification on physical device NOT_RUN",
        ],
        "errors": errors,
    }

    out_path = ROOT / "plan/evidence/phase-08-p8-a07-tenant-data-trust.json"
    out_path.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence, indent=2))
    return 0 if evidence["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
