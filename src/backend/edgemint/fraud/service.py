from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from edgemint.fraud.cases import CaseWorkflow
from edgemint.fraud.engine import evaluate_fraud
from edgemint.fraud.graph import detect_collusion, graph_signals
from edgemint.fraud.privacy import PrivacyStore
from edgemint.fraud.velocity import evaluate_velocity


def golden_trap_failed(*, expected_digest: str, observed_digest: str) -> bool:
    return expected_digest != observed_digest


INCIDENT_PLAYBOOKS: dict[str, list[str]] = {
    "collusion_detected": [
        "open_case",
        "quarantine_linked_accounts",
        "hold_rewards",
        "notify_trust_safety",
    ],
    "velocity_anomaly": [
        "observe",
        "challenge",
        "hold_rewards_if_repeated",
    ],
    "golden_trap_failure": [
        "quarantine",
        "open_case",
        "hold_rewards",
    ],
}


@dataclass
class FraudService:
    workflow: CaseWorkflow = field(default_factory=CaseWorkflow)
    privacy: PrivacyStore = field(default_factory=PrivacyStore)

    def evaluate_signals(self, raw_input: dict[str, Any]) -> dict[str, Any]:
        return evaluate_fraud(raw_input)

    def evaluate_with_context(
        self,
        *,
        signals: dict[str, bool],
        device_links: list[dict[str, str]] | None = None,
        velocity_events: list[dict[str, Any]] | None = None,
        golden_trap: dict[str, str] | None = None,
    ) -> dict[str, Any]:
        merged = dict(signals)
        if device_links:
            merged.update(graph_signals(links=device_links))
        if golden_trap:
            merged["goldenFailure"] = golden_trap_failed(
                expected_digest=golden_trap["expectedDigest"],
                observed_digest=golden_trap["observedDigest"],
            )
        result = evaluate_fraud(merged)
        extras: dict[str, Any] = {}
        if device_links:
            extras["collusion"] = detect_collusion(links=device_links)
        if velocity_events:
            extras["velocity"] = evaluate_velocity(events=velocity_events)
        if extras:
            result["context"] = extras
        return result

    def open_case_from_evaluation(
        self,
        *,
        subject_id: str,
        evaluation: dict[str, Any],
        operator_id: str,
        reason: str,
        evidence: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        case = self.workflow.open_case(
            subject_id=subject_id,
            risk_score_bps=int(evaluation["riskScoreBps"]),
            actions=list(evaluation.get("actions", [])),
            operator_id=operator_id,
            reason=reason,
            evidence=evidence or {},
        )
        return {
            "caseId": case.case_id,
            "subjectId": case.subject_id,
            "status": case.status,
            "riskScoreBps": case.risk_score_bps,
            "actions": case.actions,
            "version": case.version,
        }

    def apply_policy_actions(
        self,
        *,
        case_id: str,
        evaluation: dict[str, Any],
        subject_id: str,
        operator_id: str,
        reason: str,
    ) -> list[dict[str, Any]]:
        applied: list[dict[str, Any]] = []
        for action_name in evaluation.get("actions", []):
            if action_name == "hold_rewards":
                action = self.workflow.apply_hold(
                    case_id=case_id,
                    target_id=subject_id,
                    operator_id=operator_id,
                    reason=reason,
                )
            elif action_name == "quarantine":
                action = self.workflow.quarantine_worker(
                    case_id=case_id,
                    worker_id=subject_id,
                    operator_id=operator_id,
                    reason=reason,
                )
            else:
                continue
            applied.append(
                {
                    "actionId": action.action_id,
                    "actionType": action.action_type,
                    "targetId": action.target_id,
                    "version": action.version,
                    "status": action.status,
                }
            )
        return applied

    def incident_playbook(self, incident_type: str) -> list[str]:
        return list(INCIDENT_PLAYBOOKS.get(incident_type, ["observe"]))

    def submit_dsar(self, *, subject_id: str, request_type: str) -> dict[str, Any]:
        return self.privacy.submit_dsar(subject_id=subject_id, request_type=request_type)

    def delete_subject_data(
        self,
        *,
        subject_id: str,
        retained_records: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        return self.privacy.delete_subject_data(
            subject_id=subject_id,
            retained_records=retained_records,
        )

    def minimize_profile(self, *, subject_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        return self.privacy.minimize_profile(subject_id=subject_id, payload=payload)
