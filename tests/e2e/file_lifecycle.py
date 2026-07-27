from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from uuid import UUID

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src" / "backend"))

from edgemint.building_blocks.settings import Settings  # noqa: E402
from edgemint.files.errors import FileServiceError  # noqa: E402
from edgemint.files.lifecycle import ensure_workspace_object_key  # noqa: E402
from edgemint.files.malware import PassThroughMalwareScanner  # noqa: E402
from edgemint.files.policies import validate_upload_request, workspace_bound_object_key  # noqa: E402
from edgemint.files.storage import InMemoryObjectStorage  # noqa: E402


async def _run_contract_flow() -> list[str]:
    errors: list[str] = []
    settings = Settings(_env_file=None, environment="test", file_max_upload_bytes=1024)
    storage = InMemoryObjectStorage(settings=settings)
    scanner = PassThroughMalwareScanner()
    workspace_id = UUID(int=42)
    file_id = UUID(int=43)

    try:
        validate_upload_request(
            content_type="application/json",
            size_bytes=12,
            sha256="a" * 64,
            settings=settings,
        )
    except FileServiceError as exc:
        errors.append(f"valid upload rejected: {exc.code}")

    try:
        validate_upload_request(
            content_type="application/x-danger",
            size_bytes=12,
            sha256="a" * 64,
            settings=settings,
        )
    except FileServiceError as exc:
        if exc.code != "CONTENT_TYPE_NOT_ALLOWED":
            errors.append("unexpected error for blocked content type")
    else:
        errors.append("blocked content type was accepted")

    try:
        validate_upload_request(
            content_type="application/json",
            size_bytes=2048,
            sha256="a" * 64,
            settings=settings,
        )
    except FileServiceError as exc:
        if exc.code != "UPLOAD_SIZE_INVALID":
            errors.append("unexpected error for oversize upload")
    else:
        errors.append("oversize upload was accepted")

    object_key = workspace_bound_object_key(
        workspace_id=str(workspace_id),
        file_id=str(file_id),
        file_name="payload.json",
    )
    if not object_key.startswith(f"workspaces/{workspace_id}/"):
        errors.append("object key is not workspace-bound")
    other_workspace = UUID(int=99)
    other_key = ensure_workspace_object_key(
        workspace_id=other_workspace,
        file_id=file_id,
        file_name="payload.json",
    )
    if other_key == object_key:
        errors.append("object keys collided across workspaces")

    signed = await storage.issue_upload_url(
        workspace_id=workspace_id,
        file_id=file_id,
        file_name="payload.json",
        content_type="application/json",
        size_bytes=12,
        sha256="b" * 64,
    )
    if "memory://upload/" not in signed.upload_url:
        errors.append("memory upload URL missing contract prefix")
    from datetime import UTC, datetime

    if signed.expires_at <= datetime.now(UTC):
        errors.append("signed URL expiry missing")

    payload = b'{"ok":true}'
    digest = hashlib.sha256(payload).hexdigest()
    await storage.put_object(object_key=signed.object_key, payload=payload, sha256=digest)
    head = await storage.head_object(object_key=signed.object_key)
    if head is None or head.sha256 != digest:
        errors.append("stored object head mismatch")

    bad_scan = await scanner.scan(object_key=signed.object_key, sha256="eicar" + "0" * 59)
    if bad_scan.clean:
        errors.append("malware scanner failed to flag eicar prefix")

    await storage.delete_object(object_key=signed.object_key)
    if await storage.head_object(object_key=signed.object_key) is not None:
        errors.append("delete_object did not remove blob")

    return errors


def contract_checks() -> list[str]:
    errors: list[str] = []
    lifecycle = (ROOT / "src/backend/edgemint/files/lifecycle.py").read_text(encoding="utf-8")
    service = (ROOT / "src/backend/edgemint/services/file.py").read_text(encoding="utf-8")
    settings = (ROOT / "src/backend/edgemint/building_blocks/settings.py").read_text(encoding="utf-8")

    for token in [
        "create_upload_intent",
        "complete_upload",
        "enqueue_outbox_event",
        "write_audit_event",
        "workspace_bound_object_key",
    ]:
        if token not in lifecycle:
            errors.append(f"lifecycle missing:{token}")
    for route in [
        '"/files/upload-intents"',
        '"/files/{file_id}:complete"',
        '"/files/{file_id}"',
    ]:
        if route not in service:
            errors.append(f"file service missing route {route}")
    if "file_max_upload_bytes" not in settings or "file_signed_url_ttl_seconds" not in settings:
        errors.append("settings missing file lifecycle limits")
    return errors


def main() -> int:
    import asyncio

    errors = contract_checks()
    errors.extend(asyncio.run(_run_contract_flow()))
    report = {"status": "passed" if not errors else "failed", "errors": errors}
    print(json.dumps(report, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
