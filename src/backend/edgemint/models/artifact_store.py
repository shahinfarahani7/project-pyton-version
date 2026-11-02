"""Self-hosted model artifact store with short-lived signed download links.

Layout under ``EDGEMINT_MODEL_STORE_DIR``::

    {model_version_id}/{file_name}
    {model_version_id}/manifest.json   # fileName, sha256, sizeBytes
    {model_version_id}/.verified       # written by ``stage`` after a full SHA-256 check

A file is served only when ``.verified`` still matches the file's size and mtime, so a
replaced or truncated file is never handed out without re-staging.
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import shutil
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlencode

_STORE_DIR_ENV = "EDGEMINT_MODEL_STORE_DIR"
_SIGNING_KEY_ENV = "EDGEMINT_MODEL_DOWNLOAD_SIGNING_KEY"
_TTL_ENV = "EDGEMINT_MODEL_DOWNLOAD_URL_TTL_SECONDS"
_DEFAULT_TTL_SECONDS = 6 * 60 * 60
_MIN_SIGNING_KEY_LENGTH = 32
_MANIFEST = "manifest.json"
_MARKER = ".verified"
_HASH_CHUNK = 8 * 1024 * 1024


class ArtifactStoreError(Exception):
    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


@dataclass(frozen=True, slots=True)
class StoredArtifact:
    model_version_id: str
    file_name: str
    sha256: str
    size_bytes: int
    path: Path


def store_dir() -> Path | None:
    raw = os.environ.get(_STORE_DIR_ENV, "").strip()
    return Path(raw) if raw else None


def signing_key() -> bytes | None:
    raw = os.environ.get(_SIGNING_KEY_ENV, "").strip()
    if len(raw) < _MIN_SIGNING_KEY_LENGTH:
        return None
    return raw.encode()


def url_ttl_seconds() -> int:
    raw = os.environ.get(_TTL_ENV, "").strip()
    if not raw:
        return _DEFAULT_TTL_SECONDS
    value = int(raw)
    if value < 60 or value > 7 * 24 * 60 * 60:
        raise ArtifactStoreError("MODEL_DOWNLOAD_TTL_INVALID")
    return value


def _safe_component(value: str) -> str:
    if not value or value in {".", ".."} or "/" in value or "\\" in value or "\x00" in value:
        raise ArtifactStoreError("MODEL_ARTIFACT_NAME_INVALID")
    return value


def _model_dir(root: Path, model_version_id: str) -> Path:
    return root / _safe_component(model_version_id)


def _read_json(path: Path) -> dict[str, object] | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def _marker_matches(path: Path, marker: dict[str, object] | None, sha256: str, size_bytes: int) -> bool:
    if marker is None:
        return False
    try:
        stat = path.stat()
    except OSError:
        return False
    return (
        marker.get("sha256") == sha256
        and marker.get("sizeBytes") == size_bytes
        and marker.get("mtimeNs") == stat.st_mtime_ns
        and stat.st_size == size_bytes
    )


def find_artifact(
    model_version_id: str,
    *,
    pinned_file_name: str | None = None,
    pinned_sha256: str | None = None,
    pinned_size_bytes: int | None = None,
) -> StoredArtifact | None:
    """Return the locally staged artifact, or ``None`` when it is absent or not verified."""
    root = store_dir()
    if root is None:
        return None
    try:
        model_dir = _model_dir(root, model_version_id)
    except ArtifactStoreError:
        return None
    manifest = _read_json(model_dir / _MANIFEST)
    if manifest is None:
        return None
    file_name = manifest.get("fileName")
    sha256 = manifest.get("sha256")
    size_bytes = manifest.get("sizeBytes")
    if not isinstance(file_name, str) or not isinstance(sha256, str) or not isinstance(size_bytes, int):
        return None
    if pinned_file_name is not None and file_name != pinned_file_name:
        return None
    if pinned_sha256 is not None and sha256 != pinned_sha256:
        return None
    if pinned_size_bytes is not None and size_bytes != pinned_size_bytes:
        return None
    try:
        path = model_dir / _safe_component(file_name)
    except ArtifactStoreError:
        return None
    if not _marker_matches(path, _read_json(model_dir / _MARKER), sha256, size_bytes):
        return None
    return StoredArtifact(model_version_id, file_name, sha256, size_bytes, path)


def _signature(key: bytes, model_version_id: str, file_name: str, expires: int) -> str:
    message = f"{model_version_id}\n{file_name}\n{expires}".encode()
    return hmac.new(key, message, hashlib.sha256).hexdigest()


def signed_download_path(artifact: StoredArtifact, *, now: float | None = None) -> str | None:
    key = signing_key()
    if key is None:
        return None
    expires = int(now if now is not None else time.time()) + url_ttl_seconds()
    signature = _signature(key, artifact.model_version_id, artifact.file_name, expires)
    query = urlencode({"expires": expires, "signature": signature})
    return f"/models/{artifact.model_version_id}/files/{artifact.file_name}?{query}"


def verify_signature(
    model_version_id: str,
    file_name: str,
    *,
    expires: str | None,
    signature: str | None,
    now: float | None = None,
) -> None:
    key = signing_key()
    if key is None:
        raise ArtifactStoreError("MODEL_DOWNLOAD_SIGNING_DISABLED")
    if not expires or not signature or not expires.isdigit():
        raise ArtifactStoreError("MODEL_DOWNLOAD_SIGNATURE_INVALID")
    expected = _signature(key, model_version_id, file_name, int(expires))
    if not hmac.compare_digest(expected, signature):
        raise ArtifactStoreError("MODEL_DOWNLOAD_SIGNATURE_INVALID")
    if int(expires) < int(now if now is not None else time.time()):
        raise ArtifactStoreError("MODEL_DOWNLOAD_LINK_EXPIRED")


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(_HASH_CHUNK):
            digest.update(chunk)
    return digest.hexdigest()


def stage(
    model_version_id: str,
    source: Path,
    *,
    file_name: str,
    sha256: str,
    size_bytes: int,
    root: Path,
    move: bool = False,
) -> StoredArtifact:
    """Copy ``source`` into the store after a full size + SHA-256 check."""
    model_dir = _model_dir(root, model_version_id)
    target = model_dir / _safe_component(file_name)
    if source.stat().st_size != size_bytes:
        raise ArtifactStoreError("MODEL_ARTIFACT_SIZE_MISMATCH")
    if _sha256_file(source) != sha256:
        raise ArtifactStoreError("MODEL_ARTIFACT_SHA256_MISMATCH")
    model_dir.mkdir(parents=True, exist_ok=True)
    (model_dir / _MARKER).unlink(missing_ok=True)
    if source.resolve() != target.resolve():
        partial = target.with_name(f"{target.name}.partial")
        if move:
            shutil.move(str(source), partial)
        else:
            shutil.copyfile(source, partial)
        os.replace(partial, target)
    manifest = {
        "modelVersionId": model_version_id,
        "fileName": file_name,
        "sha256": sha256,
        "sizeBytes": size_bytes,
    }
    (model_dir / _MANIFEST).write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    marker = {"sha256": sha256, "sizeBytes": size_bytes, "mtimeNs": target.stat().st_mtime_ns}
    (model_dir / _MARKER).write_text(json.dumps(marker), encoding="utf-8")
    return StoredArtifact(model_version_id, file_name, sha256, size_bytes, target)


def _main(argv: list[str]) -> int:
    from edgemint.dev import model_artifact_proxy

    parser = argparse.ArgumentParser(prog="python -m edgemint.models.artifact_store")
    commands = parser.add_subparsers(dest="command", required=True)
    stage_cmd = commands.add_parser("stage", help="verify and copy a model file into the store")
    stage_cmd.add_argument("model_version_id")
    stage_cmd.add_argument("source", type=Path)
    stage_cmd.add_argument("--store", type=Path, default=store_dir())
    stage_cmd.add_argument("--move", action="store_true")
    status_cmd = commands.add_parser("status", help="show whether a staged model is servable")
    status_cmd.add_argument("model_version_id")
    status_cmd.add_argument("--store", type=Path, default=store_dir())
    args = parser.parse_args(argv)

    if args.store is None:
        parser.error(f"set --store or {_STORE_DIR_ENV}")
    os.environ[_STORE_DIR_ENV] = str(args.store)
    spec = model_artifact_proxy.pinned_artifact(args.model_version_id)
    if spec is None or spec.sha256 is None or spec.size_bytes is None:
        print(f"{args.model_version_id}: no pinned sha256/size; refusing to stage", file=sys.stderr)
        return 2

    if args.command == "stage":
        try:
            staged = stage(
                args.model_version_id,
                args.source,
                file_name=spec.file_name,
                sha256=spec.sha256,
                size_bytes=spec.size_bytes,
                root=args.store,
                move=args.move,
            )
        except ArtifactStoreError as exc:
            print(exc.code, file=sys.stderr)
            return 1
        print(f"staged {staged.path} sha256={staged.sha256}")
        return 0

    found = find_artifact(
        args.model_version_id,
        pinned_file_name=spec.file_name,
        pinned_sha256=spec.sha256,
        pinned_size_bytes=spec.size_bytes,
    )
    if found is None:
        print(f"{args.model_version_id}: NOT servable from {args.store}")
        return 1
    signing = (
        "enabled"
        if signing_key()
        else f"DISABLED (set {_SIGNING_KEY_ENV}, >= {_MIN_SIGNING_KEY_LENGTH} chars)"
    )
    print(f"{args.model_version_id}: servable {found.path} ({found.size_bytes} bytes); signing {signing}")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv[1:]))
