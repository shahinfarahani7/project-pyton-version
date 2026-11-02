"""Workspace API keys for machine access to tasks.

Secrets are returned once from create and rotate. Stored state keeps only the
hash, prefix, scopes, expiry and network allow-list. A key cannot grant
permission to mint further keys or read billing.
"""

from __future__ import annotations

import ipaddress
import secrets
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

from edgemint.building_blocks.ids import public_id, uuid7
from edgemint.files.idempotency import request_hash
from edgemint.security.api_keys import hash_secret, verify_api_key

GRANTABLE_SCOPES = frozenset({"customer.tasks:read", "customer.tasks:write"})
_MAX_ACTIVE_KEYS = 20
_MAX_LIFETIME = timedelta(days=366)
_PREFIX_LENGTH = 11


class ApiKeyError(Exception):
    def __init__(self, code: str, status: int = 422) -> None:
        super().__init__(code)
        self.code = code
        self.status = status


@dataclass
class StoredApiKey:
    public_id: str
    internal_id: UUID
    workspace_id: UUID
    name: str
    prefix: str
    secret_hash: bytes
    scopes: tuple[str, ...]
    allowed_cidrs: tuple[str, ...]
    status: str
    version: int
    created_at: datetime
    updated_at: datetime
    expires_at: datetime | None


@dataclass(frozen=True, slots=True)
class IssuedApiKey:
    body: dict[str, Any]
    record: StoredApiKey


@dataclass(frozen=True, slots=True)
class ApiKeyPrincipal:
    key_id: str
    workspace_id: UUID
    scopes: tuple[str, ...]
    denied_code: str | None = None


@dataclass
class _Receipt:
    workspace_id: UUID
    scope: str
    idempotency_key: str
    request_hash: str
    status_code: int
    body: dict[str, Any]


@dataclass
class ApiKeyDirectory:
    _keys: list[StoredApiKey] = field(default_factory=list)
    _receipts: list[_Receipt] = field(default_factory=list)
    _audits: list[dict[str, Any]] = field(default_factory=list)
    _events: list[dict[str, Any]] = field(default_factory=list)
    _hydrated: set[UUID] = field(default_factory=set)

    def create(
        self,
        *,
        workspace_id: UUID,
        principal_id: UUID,
        name: str,
        scopes: list[str] | tuple[str, ...],
        expires_at: datetime | None,
        allowed_cidrs: list[str] | tuple[str, ...],
        idempotency_key: str,
    ) -> dict[str, Any]:
        payload = _canonical_create(name, scopes, expires_at, allowed_cidrs)
        scope = f"createApiKey:{principal_id}:{workspace_id}"
        replay = self._replay(workspace_id, scope, idempotency_key, request_hash(payload))
        if replay is not None:
            return replay
        issued = self.issue_new(
            workspace_id=workspace_id,
            name=name,
            scopes=scopes,
            expires_at=expires_at,
            allowed_cidrs=allowed_cidrs,
        )
        self._remember(workspace_id, scope, idempotency_key, request_hash(payload), 201, issued.body)
        self._record_change(
            action="api_key.created",
            event_type="api_key.created",
            record=issued.record,
            principal_id=principal_id,
        )
        return issued.body

    def rotate(
        self,
        *,
        workspace_id: UUID,
        principal_id: UUID,
        key_id: str,
        idempotency_key: str,
    ) -> dict[str, Any]:
        payload = {"apiKeyId": key_id}
        scope = f"rotateApiKey:{principal_id}:{workspace_id}"
        replay = self._replay(workspace_id, scope, idempotency_key, request_hash(payload))
        if replay is not None:
            return replay
        record = self._require_active(workspace_id, key_id)
        secret = _new_secret()
        now = _now()
        record.secret_hash = hash_secret(secret)
        record.prefix = secret[:_PREFIX_LENGTH]
        record.version += 1
        record.updated_at = now
        body = _secret_body(record, secret)
        body.update(_command_receipt("rotateApiKey", record, now))
        self._remember(workspace_id, scope, idempotency_key, request_hash(payload), 200, body)
        self._record_change(
            action="api_key.rotated",
            event_type="api_key.rotated",
            record=record,
            principal_id=principal_id,
        )
        return body

    def revoke(
        self,
        *,
        workspace_id: UUID,
        principal_id: UUID,
        key_id: str,
        idempotency_key: str,
    ) -> dict[str, Any]:
        payload = {"apiKeyId": key_id}
        scope = f"revokeApiKey:{principal_id}:{workspace_id}"
        replay = self._replay(workspace_id, scope, idempotency_key, request_hash(payload))
        if replay is not None:
            return replay
        record = self._find(workspace_id, key_id)
        if record is None:
            raise ApiKeyError("API_KEY_NOT_FOUND", 404)
        now = _now()
        if record.status != "revoked":
            record.status = "revoked"
            record.version += 1
            record.updated_at = now
            self._record_change(
                action="api_key.revoked",
                event_type="api_key.revoked",
                record=record,
                principal_id=principal_id,
            )
        body = _command_receipt("revokeApiKey", record, now)
        body["status"] = "revoked"
        body["version"] = record.version
        self._remember(workspace_id, scope, idempotency_key, request_hash(payload), 200, body)
        return body

    def issue_new(
        self,
        *,
        workspace_id: UUID,
        name: str,
        scopes: list[str] | tuple[str, ...],
        expires_at: datetime | None,
        allowed_cidrs: list[str] | tuple[str, ...],
    ) -> IssuedApiKey:
        cleaned, normalized_scopes, normalized_cidrs, expiry = _validate_issue(
            name=name,
            scopes=scopes,
            expires_at=expires_at,
            allowed_cidrs=allowed_cidrs,
        )
        self._reject_duplicate_name(workspace_id, cleaned)
        self._reject_over_limit(workspace_id)
        secret = _new_secret()
        now = _now()
        record = StoredApiKey(
            public_id=public_id("key"),
            internal_id=uuid7(),
            workspace_id=workspace_id,
            name=cleaned,
            prefix=secret[:_PREFIX_LENGTH],
            secret_hash=hash_secret(secret),
            scopes=normalized_scopes,
            allowed_cidrs=normalized_cidrs,
            status="active",
            version=1,
            created_at=now,
            updated_at=now,
            expires_at=expiry,
        )
        self._keys.append(record)
        return IssuedApiKey(body=_secret_body(record, secret), record=record)

    def list_public(self, workspace_id: UUID) -> dict[str, Any]:
        items = [
            _public_record(item)
            for item in self._keys
            if item.workspace_id == workspace_id
        ]
        return {"items": items, "page": {"limit": 25, "hasMore": False}}

    def authenticate(self, raw_secret: str, *, client_ip: str | None) -> ApiKeyPrincipal | None:
        candidate = raw_secret.strip()
        if not candidate:
            return None
        now = _now()
        for record in self._keys:
            if record.status != "active":
                continue
            if record.expires_at is not None and record.expires_at <= now:
                continue
            if not verify_api_key(candidate, record.secret_hash):
                continue
            denied = None
            if not _ip_allowed(client_ip, record.allowed_cidrs):
                denied = "API_KEY_IP_DENIED"
            return ApiKeyPrincipal(
                key_id=record.public_id,
                workspace_id=record.workspace_id,
                scopes=record.scopes,
                denied_code=denied,
            )
        return None

    def metadata(self, record: StoredApiKey) -> dict[str, Any]:
        return {
            "name": record.name,
            "prefix": record.prefix,
            "scopes": list(record.scopes),
            "allowedCidrs": list(record.allowed_cidrs),
            "version": record.version,
        }

    def replace_workspace(self, workspace_id: UUID, records: list[StoredApiKey]) -> None:
        self._keys = [item for item in self._keys if item.workspace_id != workspace_id]
        self._keys.extend(records)
        self._hydrated.add(workspace_id)

    def is_hydrated(self, workspace_id: UUID) -> bool:
        return workspace_id in self._hydrated

    def forget_key(self, public_key_id: str) -> None:
        self._keys = [item for item in self._keys if item.public_id != public_key_id]

    def forget_receipt(self, workspace_id: UUID, scope: str, idempotency_key: str) -> None:
        self._receipts = [
            item
            for item in self._receipts
            if not (
                item.workspace_id == workspace_id
                and item.scope == scope
                and item.idempotency_key == idempotency_key
            )
        ]

    def forget_workspace(self, workspace_id: UUID) -> None:
        self._keys = [item for item in self._keys if item.workspace_id != workspace_id]
        self._receipts = [item for item in self._receipts if item.workspace_id != workspace_id]
        self._audits = [item for item in self._audits if item.get("workspaceId") != str(workspace_id)]
        self._events = [item for item in self._events if item.get("workspaceId") != str(workspace_id)]
        self._hydrated.discard(workspace_id)

    def audits_for(self, workspace_id: UUID) -> list[dict[str, Any]]:
        return [item for item in self._audits if item.get("workspaceId") == str(workspace_id)]

    def events_for(self, workspace_id: UUID) -> list[dict[str, Any]]:
        return [item for item in self._events if item.get("workspaceId") == str(workspace_id)]

    def _require_active(self, workspace_id: UUID, key_id: str) -> StoredApiKey:
        record = self._find(workspace_id, key_id)
        if record is None:
            raise ApiKeyError("API_KEY_NOT_FOUND", 404)
        if record.status == "revoked":
            raise ApiKeyError("API_KEY_REVOKED", 409)
        if record.expires_at is not None and record.expires_at <= _now():
            raise ApiKeyError("API_KEY_EXPIRED", 409)
        return record

    def _find(self, workspace_id: UUID, key_id: str) -> StoredApiKey | None:
        for record in self._keys:
            if record.workspace_id == workspace_id and record.public_id == key_id:
                return record
        return None

    def _reject_duplicate_name(self, workspace_id: UUID, name: str) -> None:
        folded = name.casefold()
        for record in self._keys:
            if record.workspace_id != workspace_id or record.status == "revoked":
                continue
            if _effective_status(record) == "expired":
                continue
            if record.name.casefold() == folded:
                raise ApiKeyError("API_KEY_NAME_CONFLICT", 409)

    def _reject_over_limit(self, workspace_id: UUID) -> None:
        active = sum(
            1
            for record in self._keys
            if record.workspace_id == workspace_id and _effective_status(record) == "active"
        )
        if active >= _MAX_ACTIVE_KEYS:
            raise ApiKeyError("API_KEY_LIMIT", 422)

    def _replay(
        self,
        workspace_id: UUID,
        scope: str,
        idempotency_key: str,
        digest: str,
    ) -> dict[str, Any] | None:
        for receipt in self._receipts:
            if receipt.workspace_id != workspace_id or receipt.scope != scope:
                continue
            if receipt.idempotency_key != idempotency_key:
                continue
            if receipt.request_hash != digest:
                raise ApiKeyError("IDEMPOTENCY_CONFLICT", 409)
            return dict(receipt.body)
        return None

    def _remember(
        self,
        workspace_id: UUID,
        scope: str,
        idempotency_key: str,
        digest: str,
        status_code: int,
        body: dict[str, Any],
    ) -> None:
        self._receipts.append(
            _Receipt(
                workspace_id=workspace_id,
                scope=scope,
                idempotency_key=idempotency_key,
                request_hash=digest,
                status_code=status_code,
                body=dict(body),
            )
        )

    def _record_change(
        self,
        *,
        action: str,
        event_type: str,
        record: StoredApiKey,
        principal_id: UUID,
    ) -> None:
        details = {
            "workspaceId": str(record.workspace_id),
            "action": action,
            "resourceId": record.public_id,
            "actorId": str(principal_id),
            "name": record.name,
            "prefix": record.prefix,
            "scopes": list(record.scopes),
            "version": record.version,
        }
        self._audits.append(details)
        self._events.append(
            {
                "workspaceId": str(record.workspace_id),
                "type": event_type,
                "aggregateId": record.public_id,
                "version": record.version,
            }
        )


directory = ApiKeyDirectory()


def _now() -> datetime:
    return datetime.now(tz=UTC)


def _new_secret() -> str:
    return f"emk_{secrets.token_urlsafe(32)}"


def _canonical_create(
    name: str,
    scopes: list[str] | tuple[str, ...],
    expires_at: datetime | None,
    allowed_cidrs: list[str] | tuple[str, ...],
) -> dict[str, Any]:
    cleaned, normalized_scopes, normalized_cidrs, expiry = _validate_issue(
        name=name,
        scopes=scopes,
        expires_at=expires_at,
        allowed_cidrs=allowed_cidrs,
    )
    return {
        "name": cleaned,
        "scopes": list(normalized_scopes),
        "expiresAt": None if expiry is None else expiry.isoformat(),
        "allowedCidrs": list(normalized_cidrs),
    }


def _validate_issue(
    *,
    name: str,
    scopes: list[str] | tuple[str, ...],
    expires_at: datetime | None,
    allowed_cidrs: list[str] | tuple[str, ...],
) -> tuple[str, tuple[str, ...], tuple[str, ...], datetime | None]:
    cleaned = name.strip()
    if not cleaned or len(cleaned) > 80:
        raise ApiKeyError("API_KEY_NAME_INVALID", 422)
    if not scopes:
        raise ApiKeyError("API_KEY_SCOPE_REQUIRED", 422)
    unknown = [scope for scope in scopes if scope not in GRANTABLE_SCOPES]
    if unknown:
        raise ApiKeyError("API_KEY_SCOPE_FORBIDDEN", 422)
    normalized_scopes = tuple(sorted(set(scopes)))
    networks: list[str] = []
    for raw in allowed_cidrs:
        candidate = raw.strip()
        if not candidate:
            continue
        try:
            network = ipaddress.ip_network(candidate, strict=False)
        except ValueError as exc:
            raise ApiKeyError("API_KEY_CIDR_INVALID", 422) from exc
        rendered = str(network)
        if rendered not in networks:
            networks.append(rendered)
    expiry = _validate_expiry(expires_at)
    return cleaned, normalized_scopes, tuple(networks), expiry


def _validate_expiry(expires_at: datetime | None) -> datetime | None:
    if expires_at is None:
        return None
    if expires_at.tzinfo is None or expires_at.utcoffset() is None:
        raise ApiKeyError("API_KEY_EXPIRY_INVALID", 422)
    expiry = expires_at.astimezone(UTC)
    now = _now()
    if expiry <= now or expiry > now + _MAX_LIFETIME:
        raise ApiKeyError("API_KEY_EXPIRY_INVALID", 422)
    return expiry


def _effective_status(record: StoredApiKey) -> str:
    if record.status == "revoked":
        return "revoked"
    if record.expires_at is not None and record.expires_at <= _now():
        return "expired"
    return "active"


def _public_record(record: StoredApiKey) -> dict[str, Any]:
    status = _effective_status(record)
    return {
        "id": record.public_id,
        "name": record.name,
        "status": status,
        "version": record.version,
        "prefix": record.prefix,
        "createdAt": record.created_at.isoformat(),
        "updatedAt": record.updated_at.isoformat(),
        "expiresAt": None if record.expires_at is None else record.expires_at.isoformat(),
        "scopes": list(record.scopes),
        "allowedCidrs": list(record.allowed_cidrs),
        "revocable": status == "active",
        "rotatable": status == "active",
    }


def _secret_body(record: StoredApiKey, secret: str) -> dict[str, Any]:
    body = _public_record(record)
    body["secret"] = secret
    body["createdAt"] = record.created_at.isoformat()
    return body


def _command_receipt(operation_id: str, record: StoredApiKey, occurred_at: datetime) -> dict[str, Any]:
    return {
        "operationId": operation_id,
        "accepted": True,
        "resourceId": record.public_id,
        "status": _effective_status(record),
        "occurredAt": occurred_at.isoformat(),
    }


def _ip_allowed(client_ip: str | None, cidrs: tuple[str, ...]) -> bool:
    if not cidrs:
        return True
    if not client_ip:
        return False
    try:
        address = ipaddress.ip_address(client_ip)
    except ValueError:
        return False
    return any(address in ipaddress.ip_network(cidr, strict=False) for cidr in cidrs)
