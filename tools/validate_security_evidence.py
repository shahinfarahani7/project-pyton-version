#!/usr/bin/env python3
"""Validate independent security verification evidence for WP-220."""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

REQUIRED_REVIEWS = (
    "summary.json",
    "threat-model-review.json",
    "penetration-test-report.json",
    "security-exception-register.json",
    "mobile-tamper-test.json",
    "api-authorization-matrix.json",
    "cloud-iam-review.json",
    "supply-chain-verification.json",
    "cryptography-review.json",
    "privacy-review.json",
    "remediation-retest.json",
    "coverage.json",
    "findings.json",
)

REQUIRED_COVERAGE_AREAS = (
    "workspaceIsolation",
    "moneyMovement",
    "workerTrust",
    "artifactSigning",
    "operationsBreakGlass",
)

REQUIRED_EXTERNAL_INPUTS = (
    "INDEPENDENT_PENETRATION_TEST_REPORT",
    "SECURITY_EXCEPTION_REGISTER",
)

FINDING_REQUIRED_FIELDS = ("id", "owner", "severity", "evidence", "remediation", "status")
HIGH_SEVERITIES = {"critical", "high"}


def _load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _parse_iso8601(value: str) -> datetime:
    normalized = value.replace("Z", "+00:00")
    return datetime.fromisoformat(normalized)


def validate_security_dir(security_dir: Path) -> tuple[list[str], dict]:
    errors: list[str] = []

    if not security_dir.is_dir():
        return [f"security evidence directory missing: {security_dir}"], {}

    for name in REQUIRED_REVIEWS:
        if not (security_dir / name).is_file():
            errors.append(f"missing security evidence: {name}")

    external_root = ROOT / "evidence" / "actual" / "external-inputs"
    for input_name in REQUIRED_EXTERNAL_INPUTS:
        external_path = external_root / f"{input_name}.json"
        if not external_path.is_file():
            errors.append(f"missing external input: {input_name}")

    if errors:
        return errors, {}

    summary = _load_json(security_dir / "summary.json")
    coverage = _load_json(security_dir / "coverage.json")
    findings_doc = _load_json(security_dir / "findings.json")
    pentest = _load_json(security_dir / "penetration-test-report.json")
    exception_register = _load_json(security_dir / "security-exception-register.json")

    if summary.get("status") != "passed":
        errors.append("security summary status is not passed")

    for review_name in REQUIRED_REVIEWS:
        if review_name in {"summary.json", "coverage.json", "findings.json"}:
            continue
        review = _load_json(security_dir / review_name)
        if review.get("status") not in {"passed", "completed"}:
            errors.append(f"{review_name} status is not passed/completed")

    pentest_ref = pentest.get("externalInputRef")
    if pentest_ref != "INDEPENDENT_PENETRATION_TEST_REPORT":
        errors.append("penetration-test-report missing externalInputRef")
    register_ref = exception_register.get("externalInputRef")
    if register_ref != "SECURITY_EXCEPTION_REGISTER":
        errors.append("security-exception-register missing externalInputRef")

    coverage_areas = coverage.get("areas", {})
    for area in REQUIRED_COVERAGE_AREAS:
        entry = coverage_areas.get(area)
        if not entry:
            errors.append(f"missing coverage area: {area}")
            continue
        if not entry.get("independentCoverage"):
            errors.append(f"coverage area lacks independent review: {area}")
        if not entry.get("reviewRef"):
            errors.append(f"coverage area missing reviewRef: {area}")

    findings = findings_doc.get("findings", [])
    if not findings:
        errors.append("findings.json must contain at least one finding")

    now = datetime.now(timezone.utc)
    open_critical_high = 0
    for finding in findings:
        finding_id = finding.get("id", "<unknown>")
        for field in FINDING_REQUIRED_FIELDS:
            if field not in finding or finding[field] in (None, ""):
                errors.append(f"finding {finding_id} missing required field: {field}")

        severity = str(finding.get("severity", "")).lower()
        status = str(finding.get("status", "")).lower()

        if severity in HIGH_SEVERITIES and status == "open":
            open_critical_high += 1
            errors.append(f"unapproved critical/high finding remains open: {finding_id}")

        if severity in HIGH_SEVERITIES and status == "risk_accepted":
            acceptance = finding.get("riskAcceptance") or {}
            if not acceptance.get("approved"):
                errors.append(f"finding {finding_id} risk acceptance not approved")
            expiry = acceptance.get("expiresAt")
            if not expiry:
                errors.append(f"finding {finding_id} risk acceptance missing expiresAt")
            else:
                if _parse_iso8601(expiry) <= now:
                    errors.append(f"finding {finding_id} risk acceptance expired")

        if status == "remediated":
            retest = finding.get("retest") or {}
            if not retest.get("passed"):
                errors.append(f"finding {finding_id} remediated without passing retest")

    result = {
        "status": "passed" if not errors else "failed",
        "securityDir": str(security_dir.relative_to(ROOT)),
        "findingCount": len(findings),
        "openCriticalHigh": open_critical_high,
        "coverageAreas": list(coverage_areas.keys()),
        "errors": errors,
    }
    return errors, result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("security_dir", nargs="?", default="evidence/actual/security")
    args = parser.parse_args()

    security_dir = Path(args.security_dir)
    if not security_dir.is_absolute():
        security_dir = ROOT / security_dir

    errors, result = validate_security_dir(security_dir)
    print(json.dumps(result, indent=2))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
