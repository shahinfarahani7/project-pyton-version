from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src" / "backend"))

from edgemint.models.errors import ModelServiceError  # noqa: E402
from edgemint.models.lifecycle import ModelVersionLifecycle  # noqa: E402
from edgemint.models.profiles import load_model_profiles  # noqa: E402
from edgemint.models.signing import build_digest_pinned_manifest  # noqa: E402


def contract_checks() -> list[str]:
    errors: list[str] = []
    registry = (ROOT / "src/backend/edgemint/models/registry.py").read_text(encoding="utf-8")
    service = (ROOT / "src/backend/edgemint/services/model_registry.py").read_text(encoding="utf-8")
    settings = (ROOT / "src/backend/edgemint/building_blocks/settings.py").read_text(encoding="utf-8")

    for token in [
        "validate_promotion_gate",
        "build_digest_pinned_manifest",
        "report_model_install",
        "start_model_rollout",
        "revoke_model",
        "rollback_model_rollout",
        "admit_download_chunk",
    ]:
        if token not in registry:
            errors.append(f"registry missing:{token}")
    for route in [
        '"/models/{model_version_id}/manifest"',
        '"/models/{model_version_id}:report-install"',
        '"/model-rollouts"',
        '"/models/{model_version_id}:revoke"',
    ]:
        if route not in service:
            errors.append(f"model-registry missing route {route}")
    for setting in ["model_registry_workspace_id", "model_chunk_size_bytes", "model_approved_licenses"]:
        if setting not in settings:
            errors.append(f"settings missing {setting}")
    lifecycle = ModelVersionLifecycle.load()
    if not lifecycle.can_transition("approved", "active"):
        errors.append("model lifecycle missing approved->active")
    return errors


def semantic_checks() -> list[str]:
    errors: list[str] = []
    profiles = load_model_profiles()
    if "paddleocr-mobile" not in profiles:
        errors.append("missing paddleocr-mobile profile")
    manifest, signature = build_digest_pinned_manifest(
        model_version_public_id="mdv_test",
        artifact_sha256="f" * 64,
        artifact_size_bytes=8192,
        runtime_abi="onnxruntime-1.18",
        license_spdx="Apache-2.0",
        chunk_size_bytes=4096,
    )
    if not signature:
        errors.append("manifest signature missing")
    if len(manifest.get("chunks") or []) < 2:
        errors.append("digest-pinned manifest missing chunks")
    try:
        from edgemint.models.distribution import reject_downgrade

        reject_downgrade(installed_version_rank=3, candidate_version_rank=1)
    except ModelServiceError as exc:
        if exc.code != "MODEL_SIGNATURE_INVALID":
            errors.append("unexpected downgrade error")
    else:
        errors.append("downgrade accepted")
    return errors


def main() -> int:
    errors = contract_checks() + semantic_checks()
    if errors:
        for item in errors:
            print(item)
        return 1
    print("model registry e2e checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
