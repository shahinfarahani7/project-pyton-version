#!/usr/bin/env python3
"""Validate CI/CD policy bindings for protected branches and production promotion."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def main() -> int:
    errors: list[str] = []
    policy = json.loads((ROOT / ".github/branch-protection-policy.json").read_text(encoding="utf-8"))
    ci = read(ROOT / ".github/workflows/ci.yml")
    release = read(ROOT / ".github/workflows/release.yml")
    build = read(ROOT / ".github/workflows/build-artifacts.yml")
    integration = read(ROOT / ".github/workflows/integration-ephemeral.yml")
    gitops = read(ROOT / ".github/workflows/gitops-promote.yml")

    for check in policy["protectedBranches"][0]["requiredStatusChecks"]:
        if f"  {check}:" not in ci:
            errors.append(f"ci.yml missing required status check job: {check}")

    for token in [
        "pip install --require-hashes -r tools/requirements.lock",
        "validate_ci_policy.py",
        "git diff --exit-code",
    ]:
        if token not in ci:
            errors.append(f"ci.yml missing control: {token}")

    for token in [
        "environment: production",
        "inputs.commit_sha",
        "COSIGN_TRUSTED_PUBLIC_KEY_SHA256",
        "production_gate.py",
    ]:
        if token not in release:
            errors.append(f"release workflow missing control: {token}")

    for token in [
        "platforms: linux/amd64,linux/arm64",
        "cosign",
        "sbom",
        "provenance",
        "SLSA",
        "vulnerability",
    ]:
        if token.lower() not in build.lower():
            errors.append(f"build-artifacts missing supply-chain control: {token}")

    for token in ["compose", "stripe_reconciliation", "privacy_deletion"]:
        if token not in integration and token not in read(ROOT / ".github/workflows/integration.yml"):
            errors.append(f"integration workflow missing check: {token}")

    for token in ["canary", "rollback", "digest", "environment: production", "github.actor"]:
        if token not in gitops:
            errors.append(f"gitops-promote missing control: {token}")

    if not (ROOT / "deploy/gitops/promotion/canary-stages.yaml").is_file():
        errors.append("missing GitOps canary stage definition")
    if not (ROOT / "deploy/gitops/rollback/previous-release.json").is_file():
        errors.append("missing GitOps rollback manifest")

    for dockerfile in (ROOT / "src/backend/services").glob("*/Dockerfile"):
        if ":latest" in dockerfile.read_text(encoding="utf-8"):
            errors.append(f"mutable latest tag in {dockerfile.relative_to(ROOT)}")

    if "/.github/" not in read(ROOT / ".github/CODEOWNERS"):
        errors.append("CODEOWNERS must cover .github/")

    if ":latest" in ci or ":latest" in build:
        errors.append("workflow uses mutable latest image tag")

    result = {
        "status": "passed" if not errors else "failed",
        "requiredChecks": policy["protectedBranches"][0]["requiredStatusChecks"],
        "errors": errors,
    }
    print(json.dumps(result, indent=2))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
