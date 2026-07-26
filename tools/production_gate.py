#!/usr/bin/env python3
"""Fail-closed production evidence gate with path, hash, chronology and signature binding."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
from datetime import datetime, timedelta, timezone

import yaml
from jsonschema import Draft202012Validator, FormatChecker

ROOT = pathlib.Path(__file__).resolve().parents[1]
ALLOWED_EVIDENCE_ROOT = (ROOT / "evidence" / "actual").resolve()


def block(code: str, detail: str = "") -> None:
    print(f"PRODUCTION_BLOCKED:{code}:{detail}")
    raise SystemExit(2)


def parse_time(value: str) -> datetime:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        block("NAIVE_TIMESTAMP", value)
    return parsed.astimezone(timezone.utc)


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def confined_file(relative: str) -> pathlib.Path:
    if "\\" in relative or relative.startswith("/"):
        block("INVALID_EVIDENCE_PATH", relative)
    candidate = (ROOT / relative).resolve(strict=True)
    try:
        candidate.relative_to(ALLOWED_EVIDENCE_ROOT)
    except ValueError:
        block("EVIDENCE_PATH_OUTSIDE_ALLOWED_ROOT", relative)
    original = ROOT / relative
    if original.is_symlink() or any(parent.is_symlink() for parent in original.parents if parent != ROOT):
        block("SYMLINK_EVIDENCE_FORBIDDEN", relative)
    if not candidate.is_file():
        block("EVIDENCE_NOT_REGULAR_FILE", relative)
    return candidate


def verify_ref(ref: dict, release_id: str, commit_sha: str, generated_at: datetime) -> pathlib.Path:
    if ref["releaseId"] != release_id or ref["commitSha"] != commit_sha:
        block("EVIDENCE_BINDING_MISMATCH", ref["path"])
    path = confined_file(ref["path"])
    if sha256_file(path) != ref["sha256"]:
        block("EVIDENCE_HASH_MISMATCH", ref["path"])
    if parse_time(ref["generatedAt"]) > generated_at:
        block("EVIDENCE_GENERATED_AFTER_MANIFEST", ref["path"])
    if path.stat().st_size == 0:
        block("EMPTY_EVIDENCE", ref["path"])
    return path


def exact_unique(data: dict, field: str, key: str, expected: list[str]) -> None:
    values = [item[key] for item in data[field]]
    if len(values) != len(set(values)):
        block(f"DUPLICATE_{field.upper()}", str(values))
    if set(values) != set(expected):
        block(f"RELEASE_SET_MISMATCH_{field.upper()}", json.dumps({"missing": sorted(set(expected)-set(values)), "extra": sorted(set(values)-set(expected))}))


def verify_json_binding(path: pathlib.Path, release_id: str, commit_sha: str, subject: str | None = None) -> dict:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        block("NON_JSON_ATTESTATION", f"{path}:{exc}")
    generic_schema = json.loads((ROOT / "evidence/schemas/evidence-attestation.schema.json").read_text(encoding="utf-8"))
    generic_errors = sorted(Draft202012Validator(generic_schema, format_checker=FormatChecker()).iter_errors(payload), key=lambda issue: list(issue.path))
    if generic_errors:
        for issue in generic_errors:
            print("PRODUCTION_BLOCKED:ATTESTATION_SCHEMA:" + ("/".join(map(str, issue.path)) or "root") + ":" + issue.message)
        raise SystemExit(2)
    if payload.get("releaseId") != release_id or payload.get("commitSha") != commit_sha:
        block("ATTESTATION_BINDING_MISMATCH", str(path))
    if subject is not None and payload.get("subject") != subject:
        block("ATTESTATION_SUBJECT_MISMATCH", f"{path}:{subject}")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence-dir", required=True)
    parser.add_argument("--expected-commit-sha", default=os.getenv("GITHUB_SHA") or os.getenv("CI_COMMIT_SHA"))
    parser.add_argument("--manifest-signature")
    parser.add_argument("--trusted-key")
    parser.add_argument("--expected-trusted-key-sha256", default=os.getenv("COSIGN_TRUSTED_PUBLIC_KEY_SHA256"))
    args = parser.parse_args()
    evidence_dir = pathlib.Path(args.evidence_dir)
    if not evidence_dir.is_absolute():
        evidence_dir = ROOT / evidence_dir
    try:
        evidence_dir = evidence_dir.resolve(strict=True)
        evidence_dir.relative_to(ALLOWED_EVIDENCE_ROOT)
    except Exception:
        block("INVALID_EVIDENCE_DIRECTORY", str(evidence_dir))
    manifest = evidence_dir / "release-evidence.json"
    if not manifest.is_file() or manifest.is_symlink():
        block("MISSING_RELEASE_EVIDENCE", str(manifest))
    schema = json.loads((ROOT / "evidence/schemas/release-evidence.schema.json").read_text(encoding="utf-8"))
    data = json.loads(manifest.read_text(encoding="utf-8"))
    errors = sorted(Draft202012Validator(schema, format_checker=FormatChecker()).iter_errors(data), key=lambda issue: list(issue.path))
    if errors:
        for issue in errors:
            print("PRODUCTION_BLOCKED:EVIDENCE_SCHEMA:" + ("/".join(map(str, issue.path)) or "root") + ":" + issue.message)
        return 2
    if not args.expected_commit_sha or len(args.expected_commit_sha) != 40:
        block("EXPECTED_COMMIT_SHA_REQUIRED")
    if data["commitSha"] != args.expected_commit_sha:
        block("COMMIT_SHA_MISMATCH", f"{data['commitSha']}!={args.expected_commit_sha}")
    required = json.loads((ROOT / "evidence/required-release-sets.json").read_text(encoding="utf-8"))
    exact_unique(data, "artifacts", "name", required["artifacts"])
    exact_unique(data, "tests", "name", required["tests"])
    exact_unique(data, "approvals", "function", required["approvals"])
    exact_unique(data, "externalInputs", "name", required["externalInputs"])
    exact_unique(data, "canary", "stage", required["canary"])
    release_id, commit_sha = data["releaseId"], data["commitSha"]
    now = datetime.now(timezone.utc)
    generated_at, expires_at = parse_time(data["generatedAt"]), parse_time(data["expiresAt"])
    if generated_at > now + timedelta(minutes=5): block("MANIFEST_FROM_FUTURE", data["generatedAt"])
    if expires_at <= now: block("EVIDENCE_EXPIRED", data["expiresAt"])
    if expires_at > generated_at + timedelta(hours=24): block("EVIDENCE_TTL_TOO_LONG", data["expiresAt"])
    trusted_roots_path = verify_ref(data["trustedRoots"], release_id, commit_sha, generated_at)
    trusted_roots_schema = json.loads((ROOT / "evidence/schemas/trusted-roots.schema.json").read_text(encoding="utf-8"))
    trusted_roots = json.loads(trusted_roots_path.read_text(encoding="utf-8"))
    trusted_root_errors = sorted(Draft202012Validator(trusted_roots_schema, format_checker=FormatChecker()).iter_errors(trusted_roots), key=lambda issue: list(issue.path))
    if trusted_root_errors:
        for issue in trusted_root_errors:
            print("PRODUCTION_BLOCKED:TRUSTED_ROOT_SCHEMA:" + ("/".join(map(str, issue.path)) or "root") + ":" + issue.message)
        return 2
    verify_json_binding(trusted_roots_path, release_id, commit_sha, "trusted-roots")
    repo_path = verify_ref(data["repositoryState"], release_id, commit_sha, generated_at)
    repository_state = verify_json_binding(repo_path, release_id, commit_sha, "repository-state")
    repository_schema = json.loads((ROOT / "evidence/schemas/repository-state.schema.json").read_text(encoding="utf-8"))
    repository_errors = sorted(Draft202012Validator(repository_schema, format_checker=FormatChecker()).iter_errors(repository_state), key=lambda issue: list(issue.path))
    if repository_errors:
        for issue in repository_errors:
            print("PRODUCTION_BLOCKED:REPOSITORY_STATE_SCHEMA:" + ("/".join(map(str, issue.path)) or "root") + ":" + issue.message)
        return 2
    if repository_state["headCommitSha"] != commit_sha:
        block("REPOSITORY_HEAD_MISMATCH", repository_state["headCommitSha"])
    if repository_state["packageManifestSha256"] != sha256_file(ROOT / "PACKAGE-MANIFEST.json"):
        block("PACKAGE_MANIFEST_BINDING_MISMATCH")
    if repository_state["checksumsSha256"] != sha256_file(ROOT / "CHECKSUMS.sha256"):
        block("CHECKSUM_FILE_BINDING_MISMATCH")
    for item in data["externalInputs"]:
        if parse_time(item["verifiedAt"]) > generated_at: block("EXTERNAL_INPUT_VERIFIED_AFTER_MANIFEST", item["name"])
        verify_json_binding(verify_ref(item["evidence"], release_id, commit_sha, generated_at), release_id, commit_sha, item["name"])
    for artifact in data["artifacts"]:
        if parse_time(artifact["producedAt"]) > generated_at: block("ARTIFACT_FROM_FUTURE", artifact["name"])
        for field in ["sbom", "signatureVerification", "provenance", "vulnerabilityReport"]:
            evidence_path = verify_ref(artifact[field], release_id, commit_sha, generated_at)
            verify_json_binding(evidence_path, release_id, commit_sha, artifact["name"])
    latest_test = datetime.min.replace(tzinfo=timezone.utc)
    for test in data["tests"]:
        started, completed = parse_time(test["startedAt"]), parse_time(test["completedAt"])
        if completed < started or completed > generated_at: block("INVALID_TEST_CHRONOLOGY", test["name"])
        latest_test = max(latest_test, completed)
        report = verify_ref(test["report"], release_id, commit_sha, generated_at)
        verify_json_binding(report, release_id, commit_sha, test["name"])
    for approval in data["approvals"]:
        if approval["releaseId"] != release_id or approval["commitSha"] != commit_sha: block("APPROVAL_BINDING_MISMATCH", approval["function"])
        approved_at = parse_time(approval["approvedAt"])
        if approved_at < latest_test or approved_at > generated_at: block("INVALID_APPROVAL_CHRONOLOGY", approval["function"])
        report = verify_ref(approval["signatureVerification"], release_id, commit_sha, generated_at)
        verify_json_binding(report, release_id, commit_sha, approval["function"])
    previous_completed = None
    stage_order = required["canary"]
    by_stage = {item["stage"]: item for item in data["canary"]}
    for stage in stage_order:
        item = by_stage[stage]
        started, completed = parse_time(item["startedAt"]), parse_time(item["completedAt"])
        if completed < started or completed > generated_at: block("INVALID_CANARY_CHRONOLOGY", stage)
        if previous_completed and started < previous_completed: block("CANARY_STAGE_OVERLAP_OR_REORDER", stage)
        previous_completed = completed
        for field in ["report", "metrics"]:
            report = verify_ref(item[field], release_id, commit_sha, generated_at)
            verify_json_binding(report, release_id, commit_sha, stage)
    if not args.manifest_signature or not args.trusted_key:
        block("DETACHED_MANIFEST_SIGNATURE_AND_TRUSTED_KEY_REQUIRED")
    cosign = shutil.which("cosign")
    if not cosign: block("COSIGN_NOT_INSTALLED")
    signature = confined_file(args.manifest_signature)
    if not args.expected_trusted_key_sha256 or not re.fullmatch(r"[a-f0-9]{64}", args.expected_trusted_key_sha256):
        block("PROTECTED_TRUSTED_KEY_SHA256_REQUIRED")
    trusted_key_source = pathlib.Path(args.trusted_key)
    if not trusted_key_source.is_absolute():
        trusted_key_source = ROOT / trusted_key_source
    if trusted_key_source.is_symlink():
        block("TRUSTED_KEY_SYMLINK_FORBIDDEN", str(trusted_key_source))
    trusted_key = trusted_key_source.resolve(strict=True)
    if not trusted_key.is_file():
        block("TRUSTED_KEY_NOT_REGULAR_FILE", str(trusted_key))
    actual_trusted_key_sha256 = sha256_file(trusted_key)
    if actual_trusted_key_sha256 != args.expected_trusted_key_sha256:
        block("TRUSTED_KEY_SHA256_MISMATCH", actual_trusted_key_sha256)
    if trusted_roots.get("cosignPublicKeySha256") != args.expected_trusted_key_sha256:
        block("TRUSTED_ROOT_ATTESTATION_MISMATCH", trusted_roots.get("cosignPublicKeySha256", "missing"))
    command = [cosign, "verify-blob", "--key", str(trusted_key), "--signature", str(signature), str(manifest)]
    completed = subprocess.run(command, capture_output=True, text=True)
    if completed.returncode != 0: block("MANIFEST_SIGNATURE_INVALID", completed.stderr[-1000:])
    print(json.dumps({"status":"production-gate-passed","releaseId":release_id,"commitSha":commit_sha}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
