from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

import yaml

DEFAULT_RUNTIME_BACKEND = "flutter_gemma_mediapipe_v1"
QWEN_MODEL_VERSION_ID = "mdv_qwen2_5_0_5b"
QWEN_PROFILE_ID = "qwen2.5-0.5b"
QWEN_ARTIFACT_FILE = "Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task"
QWEN_VERIFIED_CONTEXT_LIMIT = 1280


@dataclass(frozen=True, slots=True)
class ArtifactIdentityManifest:
    model_version_id: str
    profile_id: str
    artifact_file_name: str
    verified_context_limit: int
    runtime_backend: str
    artifact_evidence: str


@dataclass(frozen=True, slots=True)
class ArtifactIdentityEvaluation:
    consistent: bool
    reasons: tuple[str, ...]


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


@lru_cache(maxsize=1)
def load_qwen_artifact_identity_manifest() -> ArtifactIdentityManifest:
    context_path = (
        _repo_root() / "dsl" / "catalog" / "context-profiles" / "qwen2.5-0.5b-artifact-v1.yaml"
    )
    document = yaml.safe_load(context_path.read_text(encoding="utf-8"))
    spec = document["spec"]
    return ArtifactIdentityManifest(
        model_version_id=str(spec["modelVersionId"]),
        profile_id=str(document["metadata"]["name"]),
        artifact_file_name=QWEN_ARTIFACT_FILE,
        verified_context_limit=int(spec["verifiedArtifactContextLimit"]),
        runtime_backend=DEFAULT_RUNTIME_BACKEND,
        artifact_evidence=str(spec.get("artifactEvidence", "")),
    )


def evaluate_artifact_identity_consistency(
    *,
    manifest: ArtifactIdentityManifest | None = None,
    worker_catalog_model_version_id: str = QWEN_MODEL_VERSION_ID,
    worker_catalog_context_limit: int = QWEN_VERIFIED_CONTEXT_LIMIT,
    worker_catalog_file_name: str = QWEN_ARTIFACT_FILE,
) -> ArtifactIdentityEvaluation:
    active = manifest or load_qwen_artifact_identity_manifest()
    reasons: list[str] = []
    if active.model_version_id != worker_catalog_model_version_id:
        reasons.append("MODEL_VERSION_MISMATCH")
    if active.verified_context_limit != worker_catalog_context_limit:
        reasons.append("CONTEXT_LIMIT_MISMATCH")
    if active.artifact_file_name != worker_catalog_file_name:
        reasons.append("ARTIFACT_FILENAME_MISMATCH")
    if "ekv1280" not in active.artifact_file_name:
        reasons.append("ARTIFACT_EVIDENCE_MISSING_EKV1280")
    return ArtifactIdentityEvaluation(
        consistent=not reasons,
        reasons=tuple(reasons),
    )


def require_consistent_artifact_identity(
    *,
    manifest: ArtifactIdentityManifest | None = None,
) -> ArtifactIdentityManifest:
    evaluation = evaluate_artifact_identity_consistency(manifest=manifest)
    if evaluation.consistent:
        return manifest or load_qwen_artifact_identity_manifest()
    raise ValueError(f"artifact identity inconsistent: {', '.join(evaluation.reasons)}")
