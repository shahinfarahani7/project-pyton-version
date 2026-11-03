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
            "target": "application",
        }
        if self.notes:
            body["notes"] = self.notes
        return body


@dataclass(frozen=True)
class WorkerModelRelease:
    model_version_id: str
    artifact_sha256: str
    file_name: str
    notes: str | None

    def public_view(self) -> dict[str, object]:
        body: dict[str, object] = {
            "target": "model",
            "modelVersionId": self.model_version_id,
            "artifactSha256": self.artifact_sha256,
            "fileName": self.file_name,
        }
        if self.notes:
            body["notes"] = self.notes
        return body


@dataclass(frozen=True)
class WorkerUpdateCatalog:
    application: WorkerAppRelease | None
    model: WorkerModelRelease | None

    def public_view(self) -> dict[str, object]:
        application = None if self.application is None else self.application.public_view()
        model = None if self.model is None else self.model.public_view()
        if application is not None and model is not None:
            return {"updates": [application, model]}
        if application is not None:
            return application
        if model is not None:
            return model
        raise WorkerAppReleaseError(
            "WORKER_APP_RELEASE_UNCONFIGURED",
            404,
            "No worker update is published.",
        )


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


def resolve_worker_updates(settings: Settings) -> WorkerUpdateCatalog:
    """Publish an application update, a model update, or both."""
    application = _optional_app_release(settings)
    model = _optional_model_release(settings)
    if application is None and model is None:
        raise WorkerAppReleaseError(
            "WORKER_APP_RELEASE_UNCONFIGURED",
            404,
            "No worker update is published.",
        )
    return WorkerUpdateCatalog(application=application, model=model)


def _optional_app_release(settings: Settings) -> WorkerAppRelease | None:
    name = (settings.worker_app_release_version_name or "").strip()
    code = settings.worker_app_release_version_code
    raw_path = (settings.worker_app_release_apk_path or "").strip()
    digest = (settings.worker_app_release_sha256 or "").strip()
    if not name and code is None and not raw_path and not digest:
        return None
    return resolve_worker_app_release(settings)


def _optional_model_release(settings: Settings) -> WorkerModelRelease | None:
    version_id = (settings.worker_model_release_version_id or "").strip()
    digest = (settings.worker_model_release_sha256 or "").strip().lower()
    file_name = (settings.worker_model_release_file_name or "").strip()
    notes_raw = (settings.worker_model_release_notes or "").strip()
    if not version_id and not digest and not file_name:
        return None
    if (
        not version_id
        or len(version_id) > 64
        or "/" in version_id
        or "\\" in version_id
        or not file_name
        or len(file_name) > 128
        or "/" in file_name
        or "\\" in file_name
        or _SHA256_RE.fullmatch(digest) is None
    ):
        raise WorkerAppReleaseError(
            "WORKER_MODEL_RELEASE_INVALID",
            503,
            "Worker model release configuration is incomplete.",
        )
    notes = notes_raw[:_MAX_NOTES] if notes_raw else None
    return WorkerModelRelease(
        model_version_id=version_id,
        artifact_sha256=digest,
        file_name=file_name,
        notes=notes,
    )


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
