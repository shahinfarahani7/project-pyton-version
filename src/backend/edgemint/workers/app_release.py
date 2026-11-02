"""Published Android worker APK offered to installed apps."""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from pathlib import Path

from edgemint.building_blocks.settings import Settings

DOWNLOAD_PATH = "/worker-app/release/apk"
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
_MAX_VERSION_CODE = 2_147_483_647
_MAX_VERSION_NAME = 32
_MAX_NOTES = 500


class WorkerAppReleaseError(Exception):
    def __init__(self, code: str, status: int, detail: str) -> None:
        super().__init__(detail)
        self.code = code
        self.status = status
        self.detail = detail


@dataclass(frozen=True)
class WorkerAppRelease:
    version_name: str
    version_code: int
    apk_path: Path
    sha256: str
    size_bytes: int
    notes: str | None
    mandatory: bool

    def public_view(self) -> dict[str, object]:
        body: dict[str, object] = {
            "versionName": self.version_name,
            "versionCode": self.version_code,
            "downloadPath": DOWNLOAD_PATH,
            "sha256": self.sha256,
            "sizeBytes": self.size_bytes,
            "mandatory": self.mandatory,
        }
        if self.notes:
            body["notes"] = self.notes
        return body


_cache_key: tuple[object, ...] | None = None
_cache_release: WorkerAppRelease | None = None


def clear_worker_app_release_cache() -> None:
    global _cache_key, _cache_release
    _cache_key = None
    _cache_release = None


def resolve_worker_app_release(settings: Settings) -> WorkerAppRelease:
    """Return the published release, or raise when it is unset or unsafe to serve."""
    global _cache_key, _cache_release
    name = (settings.worker_app_release_version_name or "").strip()
    code = settings.worker_app_release_version_code
    raw_path = (settings.worker_app_release_apk_path or "").strip()
    digest = (settings.worker_app_release_sha256 or "").strip().lower()
    notes_raw = (settings.worker_app_release_notes or "").strip()
    notes = notes_raw[:_MAX_NOTES] if notes_raw else None
    mandatory = settings.worker_app_release_mandatory

    if not name and code is None and not raw_path and not digest:
        raise WorkerAppReleaseError(
            "WORKER_APP_RELEASE_UNCONFIGURED",
            404,
            "No worker app release is published.",
        )
    if (
        not name
        or len(name) > _MAX_VERSION_NAME
        or code is None
        or code <= 0
        or code > _MAX_VERSION_CODE
        or not raw_path
        or _SHA256_RE.fullmatch(digest) is None
    ):
        raise WorkerAppReleaseError(
            "WORKER_APP_RELEASE_INVALID",
            503,
            "Worker app release configuration is incomplete.",
        )

    path = Path(raw_path)
    if not path.is_file():
        raise WorkerAppReleaseError(
            "WORKER_APP_RELEASE_MISSING",
            503,
            "Worker app release file is missing.",
        )
    stat = path.stat()
    if stat.st_size <= 0:
        raise WorkerAppReleaseError(
            "WORKER_APP_RELEASE_MISSING",
            503,
            "Worker app release file is empty.",
        )
    key = (
        str(path.resolve()),
        stat.st_mtime_ns,
        stat.st_size,
        digest,
        name,
        code,
        notes,
        mandatory,
    )
    if _cache_key == key and _cache_release is not None:
        return _cache_release
    actual = _sha256_file(path)
    if actual != digest:
        raise WorkerAppReleaseError(
            "WORKER_APP_RELEASE_HASH_MISMATCH",
            503,
            "Worker app release file does not match the published checksum.",
        )
    release = WorkerAppRelease(
        version_name=name,
        version_code=code,
        apk_path=path.resolve(),
        sha256=digest,
        size_bytes=stat.st_size,
        notes=notes,
        mandatory=mandatory,
    )
    _cache_key = key
    _cache_release = release
    return release


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
