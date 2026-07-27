from __future__ import annotations

import hashlib
from uuid import UUID

import pytest
from edgemint.building_blocks.settings import Settings
from edgemint.files.errors import FileServiceError
from edgemint.files.malware import PassThroughMalwareScanner
from edgemint.files.policies import validate_upload_request, workspace_bound_object_key
from edgemint.files.storage import InMemoryObjectStorage


@pytest.fixture
def settings() -> Settings:
    return Settings(_env_file=None, environment="test", file_max_upload_bytes=1024)


def test_rejects_disallowed_content_type(settings: Settings) -> None:
    with pytest.raises(FileServiceError) as exc:
        validate_upload_request(
            content_type="application/x-executable",
            size_bytes=10,
            sha256="a" * 64,
            settings=settings,
        )
    assert exc.value.code == "CONTENT_TYPE_NOT_ALLOWED"


def test_rejects_oversize_upload(settings: Settings) -> None:
    with pytest.raises(FileServiceError) as exc:
        validate_upload_request(
            content_type="application/json",
            size_bytes=2048,
            sha256="a" * 64,
            settings=settings,
        )
    assert exc.value.code == "UPLOAD_SIZE_INVALID"


def test_workspace_bound_object_keys_are_isolated() -> None:
    workspace_a = UUID(int=1)
    workspace_b = UUID(int=2)
    file_id = UUID(int=3)
    key_a = workspace_bound_object_key(
        workspace_id=str(workspace_a),
        file_id=str(file_id),
        file_name="a.json",
    )
    key_b = workspace_bound_object_key(
        workspace_id=str(workspace_b),
        file_id=str(file_id),
        file_name="a.json",
    )
    assert key_a != key_b
    assert str(workspace_a) in key_a
    assert str(workspace_b) in key_b


@pytest.mark.asyncio
async def test_in_memory_storage_verifies_sha256(settings: Settings) -> None:
    storage = InMemoryObjectStorage(settings=settings)
    workspace_id = UUID(int=10)
    file_id = UUID(int=11)
    signed = await storage.issue_upload_url(
        workspace_id=workspace_id,
        file_id=file_id,
        file_name="payload.json",
        content_type="application/json",
        size_bytes=4,
        sha256="c" * 64,
    )
    payload = b"data"
    digest = hashlib.sha256(payload).hexdigest()
    with pytest.raises(FileServiceError) as exc:
        await storage.put_object(object_key=signed.object_key, payload=payload, sha256="d" * 64)
    assert exc.value.code == "FILE_DIGEST_MISMATCH"
    head = await storage.put_object(object_key=signed.object_key, payload=payload, sha256=digest)
    assert head.sha256 == digest


@pytest.mark.asyncio
async def test_malware_scanner_flags_eicar_prefix() -> None:
    scanner = PassThroughMalwareScanner()
    result = await scanner.scan(object_key="any", sha256="eicar" + "0" * 59)
    assert result.clean is False
