from __future__ import annotations

from dataclasses import dataclass

from edgemint.building_blocks.settings import Settings, get_settings
from edgemint.models.errors import model_error
from edgemint.models.signing import verify_manifest_signature


@dataclass(frozen=True, slots=True)
class ReleaseEvidence:
    artifact_sha256: str
    signature_sha256: str
    license_spdx: str
    license_status: str
    benchmark_evidence_path: str | None
    rollback_version_id: str | None
    manifest: dict


def validate_promotion_gate(evidence: ReleaseEvidence, *, settings: Settings | None = None) -> None:
    active = settings or get_settings()
    if len(evidence.artifact_sha256) != 64:
        raise model_error("MODEL_RELEASE_EVIDENCE_MISSING", detail="artifact sha256 required")
    if evidence.manifest.get("artifactSha256") != evidence.artifact_sha256:
        raise model_error("MODEL_DIGEST_MISMATCH")
    verify_manifest_signature(evidence.manifest, signature_sha256=evidence.signature_sha256, settings=active)
    if evidence.license_status != "approved":
        raise model_error("MODEL_RELEASE_EVIDENCE_MISSING", detail="license not approved")
    approved = {item.strip() for item in active.model_approved_licenses.split(",") if item.strip()}
    if evidence.license_spdx not in approved:
        raise model_error("MODEL_RELEASE_EVIDENCE_MISSING", detail="license spdx not approved")
    if not evidence.benchmark_evidence_path:
        raise model_error("MODEL_RELEASE_EVIDENCE_MISSING", detail="benchmark evidence required")
    if not evidence.rollback_version_id:
        raise model_error("MODEL_RELEASE_EVIDENCE_MISSING", detail="rollback version required")
