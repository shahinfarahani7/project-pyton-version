#!/usr/bin/env python3
"""Verify CI release artifact evidence is digest-pinned, signed, scanned, and traceable."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parents[1]
DIGEST_RE = re.compile(r"^sha256:[a-f0-9]{64}$")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_attestation(path: Path, schema: dict, *, subject: str, digest: str) -> list[str]:
    errors: list[str] = []
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        return [f"{path}: invalid json: {exc}"]
    for issue in Draft202012Validator(schema, format_checker=FormatChecker()).iter_errors(payload):
        errors.append(f"{path}: schema:{issue.message}")
    if payload.get("subject") != subject:
        errors.append(f"{path}: subject mismatch")
    if payload.get("verified") is not True:
        errors.append(f"{path}: verified must be true")
    if digest and payload.get("digest") and payload["digest"] != digest:
        errors.append(f"{path}: digest mismatch")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence-dir", default="evidence/actual")
    args = parser.parse_args()
    evidence_dir = Path(args.evidence_dir)
    if not evidence_dir.is_absolute():
        evidence_dir = ROOT / evidence_dir

    errors: list[str] = []
    attestation_schema = json.loads((ROOT / "evidence/schemas/evidence-attestation.schema.json").read_text(encoding="utf-8"))
    ci_values = yaml.safe_load((ROOT / "deploy/helm/edgemint/values-ci.yaml").read_text(encoding="utf-8"))
    services = ci_values.get("services", {})
    manifest_path = evidence_dir / "ci" / "manifest.json"
    if not manifest_path.is_file():
        errors.append("missing ci release manifest")
    else:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if manifest.get("artifactCount") != len(services):
            errors.append("ci manifest artifact count mismatch")
        for name, svc in services.items():
            digest = svc.get("image", {}).get("digest", "")
            if not DIGEST_RE.fullmatch(digest):
                errors.append(f"{name}: invalid helm digest")
            artifact = next((item for item in manifest.get("artifacts", []) if item["name"] == name), None)
            if artifact is None:
                errors.append(f"{name}: missing from ci manifest")
                continue
            if artifact.get("digest") != digest:
                errors.append(f"{name}: manifest digest mismatch")
            for field in ["sbom", "signatureVerification", "provenance", "vulnerabilityReport"]:
                rel = artifact.get(field)
                if not rel:
                    errors.append(f"{name}: missing {field}")
                    continue
                path = ROOT / rel
                if not path.is_file():
                    errors.append(f"{name}: missing file {rel}")
                    continue
                if sha256_file(path) != artifact.get(f"{field}Sha256"):
                    errors.append(f"{name}: hash mismatch for {field}")
                errors.extend(verify_attestation(path, attestation_schema, subject=name, digest=digest))

    rollback = ROOT / "deploy/gitops/rollback/previous-release.json"
    if rollback.is_file():
        rollback_doc = json.loads(rollback.read_text(encoding="utf-8"))
        if not DIGEST_RE.fullmatch(rollback_doc.get("previousDigest", "")):
            errors.append("rollback manifest missing previous signed digest")
    else:
        errors.append("missing rollback manifest")

    wp_dir = evidence_dir / "work-packages"
    if not wp_dir.is_dir() or not any(wp_dir.glob("wp-*.json")):
        errors.append("missing work-package evidence")

    result = {
        "status": "passed" if not errors else "failed",
        "services": len(services),
        "evidenceDir": str(evidence_dir.relative_to(ROOT)),
        "errors": errors,
    }
    print(json.dumps(result, indent=2))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
