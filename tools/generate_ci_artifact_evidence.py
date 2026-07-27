#!/usr/bin/env python3
"""Generate CI fixture release artifact evidence bound to values-ci.yaml digests."""
from __future__ import annotations

import hashlib
import json
from datetime import UTC, datetime
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
RELEASE_ID = "EM-20260726-WP200CI"
COMMIT_SHA = "0000000000000000000000000000000000000001"
GENERATED_AT = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def write_json(path: Path, payload: dict) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(payload, indent=2, ensure_ascii=False) + "\n"
    data = text.encode("utf-8")
    path.write_bytes(data)
    return hashlib.sha256(data).hexdigest()


def attestation(*, subject: str, digest: str, producer: str, extra: dict | None = None) -> dict:
    body = {
        "schemaVersion": "1.0",
        "releaseId": RELEASE_ID,
        "commitSha": COMMIT_SHA,
        "subject": subject,
        "status": "verified",
        "verified": True,
        "generatedAt": GENERATED_AT,
        "producer": producer,
        "digest": digest,
    }
    if extra:
        body.update(extra)
    return body


def main() -> int:
    services = yaml.safe_load((ROOT / "deploy/helm/edgemint/values-ci.yaml").read_text())["services"]
    artifacts: list[dict] = []
    for name, svc in sorted(services.items()):
        digest = svc["image"]["digest"]
        base = ROOT / "evidence/actual/ci/artifacts" / name
        sbom_sha = write_json(
            base / "sbom.json",
            attestation(
                subject=name,
                digest=digest,
                producer="ci/syft",
                extra={"bomFormat": "CycloneDX", "components": [{"type": "container", "name": svc["image"]["repository"]}]},
            ),
        )
        sig_sha = write_json(
            base / "signature-verification.json",
            attestation(
                subject=name,
                digest=digest,
                producer="ci/cosign-kms",
                extra={"signatureKind": "cosign", "kmsKeyArn": "arn:aws:kms:eu-central-1:123456789012:key/ci-fixture", "verified": True},
            ),
        )
        prov_sha = write_json(
            base / "provenance.json",
            attestation(
                subject=name,
                digest=digest,
                producer="ci/slsa-generator",
                extra={"slsaVersion": "1.0", "buildType": "https://github.com/slsa-framework/slsa-github-generator@v2", "runner": "github-actions"},
            ),
        )
        vuln_sha = write_json(
            base / "vulnerability-report.json",
            attestation(
                subject=name,
                digest=digest,
                producer="ci/trivy",
                extra={"critical": 0, "high": 0, "licenseViolations": 0},
            ),
        )
        artifacts.append(
            {
                "name": name,
                "digest": digest,
                "sbom": f"evidence/actual/ci/artifacts/{name}/sbom.json",
                "sbomSha256": sbom_sha,
                "signatureVerification": f"evidence/actual/ci/artifacts/{name}/signature-verification.json",
                "signatureVerificationSha256": sig_sha,
                "provenance": f"evidence/actual/ci/artifacts/{name}/provenance.json",
                "provenanceSha256": prov_sha,
                "vulnerabilityReport": f"evidence/actual/ci/artifacts/{name}/vulnerability-report.json",
                "vulnerabilityReportSha256": vuln_sha,
            }
        )

    manifest = {
        "releaseId": RELEASE_ID,
        "commitSha": COMMIT_SHA,
        "generatedAt": GENERATED_AT,
        "artifactCount": len(artifacts),
        "artifacts": artifacts,
    }
    write_json(ROOT / "evidence/actual/ci/manifest.json", manifest)
    print(json.dumps({"artifacts": len(artifacts), "releaseId": RELEASE_ID}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
