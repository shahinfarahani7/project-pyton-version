from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import uuid4

from edgemint.operations.errors import operations_error
from edgemint.operations.masking import mask_sensitive_payload
from edgemint.operations.policy import (
    BREAK_GLASS_TTL_MINUTES,
    HIGH_RISK_ACTIONS,
    REASON_CODES,
    ROLE_PERMISSIONS,
)


@dataclass(frozen=True, slots=True)
class AuditRecord:
    audit_id: str
    operator_id: str
    action: str
    resource_id: str
    reason_code: str
    ticket_id: str
    expected_version: int | None
    occurred_at: str
    break_glass: bool


@dataclass
class PendingApproval:
    approval_id: str
    action: str
    resource_id: str
    requester_id: str
    reason_code: str
    ticket_id: str
    expected_version: int | None
    status: str = "pending"


@dataclass
class BreakGlassSession:
    session_id: str
    operator_id: str
    reason_code: str
    ticket_id: str
    activated_at: datetime
    expires_at: datetime
    paged: bool
    reviewed: bool = False


@dataclass
class OperationsService:
    audit_log: list[AuditRecord] = field(default_factory=list)
    pending_approvals: dict[str, PendingApproval] = field(default_factory=dict)
    break_glass_sessions: dict[str, BreakGlassSession] = field(default_factory=dict)
    session_recording_hooks: list[dict[str, Any]] = field(default_factory=list)
    resource_versions: dict[str, int] = field(default_factory=dict)
    catalog: dict[str, list[dict[str, Any]]] = field(
        default_factory=lambda: {
            "tasks": [],
            "workers": [],
            "models": [],
            "fraudCases": [],
            "disputes": [],
            "reconciliations": [],
            "incidents": [],
        }
    )

    def seed_catalog(self) -> None:
        if self.catalog["tasks"]:
            return
        self.catalog["tasks"] = [
            {"id": "tsk_ops_1", "taskType": "document.ocr", "status": "running", "version": 3},
        ]
        self.catalog["workers"] = [
            {"id": "wrk_ops_1", "status": "active", "tier": "T2", "trustScoreBps": 9200, "version": 2},
        ]
        self.catalog["models"] = [
            {"id": "mdl_ops_1", "status": "approved", "version": 5},
        ]
        self.catalog["fraudCases"] = [
            {"id": "frd_ops_1", "status": "open", "version": 1},
        ]
        self.catalog["disputes"] = [
            {"id": "dsp_ops_1", "status": "open", "version": 1},
        ]
        self.catalog["reconciliations"] = [
            {"id": "rec_ops_1", "status": "balanced", "version": 1},
        ]
        self.catalog["incidents"] = [
            {"id": "inc_ops_1", "status": "investigating", "version": 1},
        ]
        for items in self.catalog.values():
            for item in items:
                self.resource_versions[item["id"]] = int(item["version"])

    def operator_permissions(self, role: str) -> frozenset[str]:
        return ROLE_PERMISSIONS.get(role, frozenset())

    def search(self, *, view: str) -> list[dict[str, Any]]:
        self.seed_catalog()
        key = {
            "tasks": "tasks",
            "workers": "workers",
            "models": "models",
            "fraud": "fraudCases",
            "disputes": "disputes",
            "reconciliation": "reconciliations",
            "incidents": "incidents",
        }.get(view)
        if key is None:
            raise operations_error("INPUT_SCHEMA_INVALID", detail=f"unknown view {view}")
        return [mask_sensitive_payload(item) for item in self.catalog[key]]

    def submit_mutating_action(
        self,
        *,
        operator_id: str,
        role: str,
        action: str,
        resource_id: str,
        reason_code: str,
        ticket_id: str,
        expected_version: int | None,
        permission: str,
    ) -> dict[str, Any]:
        self._validate_reason(reason_code, ticket_id)
        self._require_permission(role, permission)
        if action in HIGH_RISK_ACTIONS:
            approval = PendingApproval(
                approval_id=f"apv_{uuid4().hex[:16]}",
                action=action,
                resource_id=resource_id,
                requester_id=operator_id,
                reason_code=reason_code,
                ticket_id=ticket_id,
                expected_version=expected_version,
            )
            self.pending_approvals[approval.approval_id] = approval
            self._record_session_hook("approval.requested", operator_id, approval.approval_id)
            return {"status": "pending_approval", "approvalId": approval.approval_id}

        return self._execute(
            operator_id=operator_id,
            role=role,
            action=action,
            resource_id=resource_id,
            reason_code=reason_code,
            ticket_id=ticket_id,
            expected_version=expected_version,
            permission=permission,
        )

    def approve_action(self, *, approver_id: str, role: str, approval_id: str) -> dict[str, Any]:
        self._require_permission(role, "operations.approve")
        approval = self.pending_approvals.get(approval_id)
        if approval is None:
            raise operations_error("TENANT_RESOURCE_NOT_FOUND", detail="approval not found")
        if approval.requester_id == approver_id:
            raise operations_error("APPROVAL_SELF_DENIED")
        if approval.status != "pending":
            raise operations_error("IDEMPOTENCY_CONFLICT")
        approval.status = "approved"
        return self._execute(
            operator_id=approver_id,
            role=role,
            action=approval.action,
            resource_id=approval.resource_id,
            reason_code=approval.reason_code,
            ticket_id=approval.ticket_id,
            expected_version=approval.expected_version,
            permission="operations.approve",
            approval_id=approval_id,
        )

    def activate_break_glass(
        self,
        *,
        operator_id: str,
        role: str,
        reason_code: str,
        ticket_id: str,
    ) -> BreakGlassSession:
        self._validate_reason(reason_code, ticket_id)
        self._require_permission(role, "operations.break_glass")
        now = datetime.now(UTC)
        session = BreakGlassSession(
            session_id=f"bg_{uuid4().hex[:16]}",
            operator_id=operator_id,
            reason_code=reason_code,
            ticket_id=ticket_id,
            activated_at=now,
            expires_at=now + timedelta(minutes=BREAK_GLASS_TTL_MINUTES),
            paged=True,
        )
        self.break_glass_sessions[session.session_id] = session
        self._append_audit(
            operator_id=operator_id,
            action="break_glass.activate",
            resource_id=session.session_id,
            reason_code=reason_code,
            ticket_id=ticket_id,
            expected_version=None,
            break_glass=True,
        )
        self._record_session_hook("break_glass.activated", operator_id, session.session_id)
        return session

    def break_glass_active(self, *, operator_id: str) -> BreakGlassSession | None:
        now = datetime.now(UTC)
        for session in self.break_glass_sessions.values():
            if session.operator_id != operator_id:
                continue
            if session.expires_at <= now:
                continue
            return session
        return None

    def export_audited_view(self, *, view: str, operator_id: str) -> dict[str, Any]:
        items = self.search(view=view)
        export_id = f"exp_{uuid4().hex[:16]}"
        self._append_audit(
            operator_id=operator_id,
            action="export.audited",
            resource_id=export_id,
            reason_code="security_review",
            ticket_id=export_id,
            expected_version=None,
            break_glass=False,
        )
        return {"exportId": export_id, "view": view, "itemCount": len(items), "items": items}

    def _execute(
        self,
        *,
        operator_id: str,
        role: str,
        action: str,
        resource_id: str,
        reason_code: str,
        ticket_id: str,
        expected_version: int | None,
        permission: str,
        approval_id: str | None = None,
    ) -> dict[str, Any]:
        self._require_permission(role, permission)
        current = self.resource_versions.get(resource_id)
        if expected_version is not None and current is not None and expected_version != current:
            raise operations_error("ETAG_MISMATCH", detail=f"expected={expected_version} actual={current}")

        if current is not None:
            self.resource_versions[resource_id] = current + 1

        receipt = {
            "operationId": f"op_{uuid4().hex[:16]}",
            "accepted": True,
            "resourceId": resource_id,
            "status": "completed",
            "occurredAt": datetime.now(UTC).isoformat(),
            **({"approvalId": approval_id} if approval_id else {}),
        }
        self._append_audit(
            operator_id=operator_id,
            action=action,
            resource_id=resource_id,
            reason_code=reason_code,
            ticket_id=ticket_id,
            expected_version=expected_version,
            break_glass=self.break_glass_active(operator_id=operator_id) is not None,
        )
        self._record_session_hook("mutation.executed", operator_id, receipt["operationId"])
        return receipt

    def _validate_reason(self, reason_code: str, ticket_id: str) -> None:
        if reason_code not in REASON_CODES:
            raise operations_error("INPUT_SCHEMA_INVALID", detail="invalid reasonCode")
        if not ticket_id.strip():
            raise operations_error("INPUT_SCHEMA_INVALID", detail="ticketId required")

    def _require_permission(self, role: str, permission: str) -> None:
        if permission not in self.operator_permissions(role):
            raise operations_error("AUTH_SCOPE_REQUIRED", detail=permission)

    def _append_audit(
        self,
        *,
        operator_id: str,
        action: str,
        resource_id: str,
        reason_code: str,
        ticket_id: str,
        expected_version: int | None,
        break_glass: bool,
    ) -> None:
        self.audit_log.append(
            AuditRecord(
                audit_id=f"aud_{uuid4().hex[:16]}",
                operator_id=operator_id,
                action=action,
                resource_id=resource_id,
                reason_code=reason_code,
                ticket_id=ticket_id,
                expected_version=expected_version,
                occurred_at=datetime.now(UTC).isoformat(),
                break_glass=break_glass,
            )
        )

    def _record_session_hook(self, event: str, operator_id: str, correlation_id: str) -> None:
        self.session_recording_hooks.append(
            {
                "event": event,
                "operatorId": operator_id,
                "correlationId": correlation_id,
                "recordedAt": datetime.now(UTC).isoformat(),
            }
        )
