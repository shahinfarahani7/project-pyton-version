from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any
from uuid import uuid4

from edgemint.fraud.errors import fraud_error
from edgemint.fraud.policy import load_fraud_policy


@dataclass(frozen=True, slots=True)
class FraudAuditRecord:
    audit_id: str
    case_id: str
    action_id: str
    operator_id: str
    action_type: str
    reason: str
    occurred_at: str
    reversible: bool


@dataclass
class FraudAction:
    action_id: str
    case_id: str
    action_type: str
    target_id: str
    version: int
    status: str
    reason: str
    operator_id: str
    created_at: str
    reversed_by: str | None = None
    appeal_allowed: bool = True


@dataclass
class FraudCase:
    case_id: str
    subject_id: str
    status: str
    risk_score_bps: int
    actions: list[str]
    version: int
    opened_at: str
    evidence: dict[str, Any] = field(default_factory=dict)
    appeals: list[dict[str, Any]] = field(default_factory=list)


@dataclass
class CaseWorkflow:
    cases: dict[str, FraudCase] = field(default_factory=dict)
    action_log: dict[str, FraudAction] = field(default_factory=dict)
    audit_log: list[FraudAuditRecord] = field(default_factory=list)
    holds: dict[str, list[str]] = field(default_factory=dict)
    quarantined: set[str] = field(default_factory=set)

    def open_case(
        self,
        *,
        subject_id: str,
        risk_score_bps: int,
        actions: list[str],
        operator_id: str,
        reason: str,
        evidence: dict[str, Any] | None = None,
    ) -> FraudCase:
        case_id = f"frd_{uuid4().hex[:16]}"
        case = FraudCase(
            case_id=case_id,
            subject_id=subject_id,
            status="open",
            risk_score_bps=risk_score_bps,
            actions=list(actions),
            version=1,
            opened_at=datetime.now(UTC).isoformat(),
            evidence=evidence or {},
        )
        self.cases[case_id] = case
        self._record_audit(
            case_id=case_id,
            action_id=f"act_{uuid4().hex[:12]}",
            operator_id=operator_id,
            action_type="open_case",
            reason=reason,
            reversible=False,
        )
        return case

    def apply_hold(self, *, case_id: str, target_id: str, operator_id: str, reason: str) -> FraudAction:
        case = self._require_case(case_id)
        action = self._create_action(
            case_id=case_id,
            action_type="hold_rewards",
            target_id=target_id,
            operator_id=operator_id,
            reason=reason,
            version=case.version + 1,
        )
        self.holds.setdefault(target_id, []).append(action.action_id)
        case.version += 1
        return action

    def quarantine_worker(
        self, *, case_id: str, worker_id: str, operator_id: str, reason: str
    ) -> FraudAction:
        case = self._require_case(case_id)
        action = self._create_action(
            case_id=case_id,
            action_type="quarantine",
            target_id=worker_id,
            operator_id=operator_id,
            reason=reason,
            version=case.version + 1,
        )
        self.quarantined.add(worker_id)
        case.version += 1
        return action

    def submit_appeal(
        self,
        *,
        case_id: str,
        submitter_id: str,
        evidence: dict[str, Any],
    ) -> dict[str, Any]:
        policy = load_fraud_policy().spec
        if not policy.get("appealAllowed", False):
            raise fraud_error("APPEAL_NOT_ALLOWED")
        case = self._require_case(case_id)
        appeal = {
            "appealId": f"apl_{uuid4().hex[:16]}",
            "submittedBy": submitter_id,
            "submittedAt": datetime.now(UTC).isoformat(),
            "evidence": evidence,
            "status": "pending_review",
        }
        case.appeals.append(appeal)
        case.version += 1
        return appeal

    def reverse_action(self, *, case_id: str, action_id: str, operator_id: str, reason: str) -> FraudAction:
        action = self.action_log.get(action_id)
        if action is None or action.case_id != case_id:
            raise fraud_error("CASE_NOT_FOUND", detail=f"action {action_id} not found")
        if not action.appeal_allowed or action.status == "reversed":
            raise fraud_error("REVERSAL_NOT_PERMITTED")
        if action.action_type == "quarantine":
            self.quarantined.discard(action.target_id)
        if action.action_type == "hold_rewards":
            holds = self.holds.get(action.target_id, [])
            if action.action_id in holds:
                holds.remove(action.action_id)
        action.status = "reversed"
        action.reversed_by = operator_id
        case = self._require_case(case_id)
        case.version += 1
        reversal = self._create_action(
            case_id=case_id,
            action_type="reverse",
            target_id=action.target_id,
            operator_id=operator_id,
            reason=reason,
            version=case.version,
            appeal_allowed=False,
        )
        self._record_audit(
            case_id=case_id,
            action_id=reversal.action_id,
            operator_id=operator_id,
            action_type="reverse",
            reason=reason,
            reversible=False,
        )
        return reversal

    def _require_case(self, case_id: str) -> FraudCase:
        case = self.cases.get(case_id)
        if case is None:
            raise fraud_error("CASE_NOT_FOUND", detail=case_id)
        return case

    def _create_action(
        self,
        *,
        case_id: str,
        action_type: str,
        target_id: str,
        operator_id: str,
        reason: str,
        version: int,
        appeal_allowed: bool = True,
    ) -> FraudAction:
        action = FraudAction(
            action_id=f"act_{uuid4().hex[:16]}",
            case_id=case_id,
            action_type=action_type,
            target_id=target_id,
            version=version,
            status="applied",
            reason=reason,
            operator_id=operator_id,
            created_at=datetime.now(UTC).isoformat(),
            appeal_allowed=appeal_allowed,
        )
        self.action_log[action.action_id] = action
        self._record_audit(
            case_id=case_id,
            action_id=action.action_id,
            operator_id=operator_id,
            action_type=action_type,
            reason=reason,
            reversible=appeal_allowed,
        )
        return action

    def _record_audit(
        self,
        *,
        case_id: str,
        action_id: str,
        operator_id: str,
        action_type: str,
        reason: str,
        reversible: bool,
    ) -> None:
        self.audit_log.append(
            FraudAuditRecord(
                audit_id=f"aud_{uuid4().hex[:16]}",
                case_id=case_id,
                action_id=action_id,
                operator_id=operator_id,
                action_type=action_type,
                reason=reason,
                occurred_at=datetime.now(UTC).isoformat(),
                reversible=reversible,
            )
        )
