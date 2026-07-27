from __future__ import annotations

import pytest
from edgemint.fraud.errors import FraudServiceError
from edgemint.fraud.service import FraudService


@pytest.fixture
def service() -> FraudService:
    return FraudService()


def test_fraud_engine_matches_policy_bands(service: FraudService) -> None:
    clean = {
        "impossibleSpeed": False,
        "goldenFailure": False,
        "invalidModelDigest": False,
        "replayNonce": False,
        "linkedAccounts": False,
    }
    low = service.evaluate_signals(clean)
    assert low["riskScoreBps"] == 0
    assert low["actions"] == []
    high = service.evaluate_signals(
        {
            **clean,
            "impossibleSpeed": True,
            "goldenFailure": True,
            "invalidModelDigest": True,
        }
    )
    assert high["riskScoreBps"] == 7500
    assert "quarantine" in high["actions"]
    assert high["rewardHold"] is True


def test_collusion_detection_merges_graph_signals(service: FraudService) -> None:
    result = service.evaluate_with_context(
        signals={
            "impossibleSpeed": False,
            "goldenFailure": False,
            "invalidModelDigest": False,
            "replayNonce": False,
            "linkedAccounts": False,
        },
        device_links=[
            {"accountId": "acc_a", "deviceId": "dev_1"},
            {"accountId": "acc_b", "deviceId": "dev_1"},
        ],
    )
    assert result["riskScoreBps"] >= 1000
    assert result["context"]["collusion"]["collusionDetected"] is True


def test_case_actions_are_versioned_and_audited(service: FraudService) -> None:
    evaluation = service.evaluate_signals(
        {
            "impossibleSpeed": True,
            "goldenFailure": True,
            "invalidModelDigest": True,
            "replayNonce": True,
            "linkedAccounts": True,
        }
    )
    case = service.open_case_from_evaluation(
        subject_id="wrk_1",
        evaluation=evaluation,
        operator_id="op_fraud",
        reason="automated_score",
    )
    applied = service.apply_policy_actions(
        case_id=case["caseId"],
        evaluation=evaluation,
        subject_id="wrk_1",
        operator_id="op_fraud",
        reason="policy_band",
    )
    assert len(applied) >= 2
    assert len(service.workflow.audit_log) >= 3
    assert "wrk_1" in service.workflow.quarantined


def test_appeal_and_reversal_when_policy_permits(service: FraudService) -> None:
    evaluation = {"riskScoreBps": 7500, "actions": ["hold_rewards", "quarantine"], "rewardHold": True}
    case = service.open_case_from_evaluation(
        subject_id="wrk_2",
        evaluation=evaluation,
        operator_id="op_fraud",
        reason="manual_review",
    )
    applied = service.apply_policy_actions(
        case_id=case["caseId"],
        evaluation=evaluation,
        subject_id="wrk_2",
        operator_id="op_fraud",
        reason="enforce",
    )
    hold_action_id = next(item["actionId"] for item in applied if item["actionType"] == "hold_rewards")
    appeal = service.workflow.submit_appeal(
        case_id=case["caseId"],
        submitter_id="wrk_2",
        evidence={"statement": "shared household device"},
    )
    assert appeal["status"] == "pending_review"
    reversal = service.workflow.reverse_action(
        case_id=case["caseId"],
        action_id=hold_action_id,
        operator_id="op_appeals",
        reason="appeal_accepted",
    )
    assert reversal.action_type == "reverse"
    assert hold_action_id not in service.workflow.holds.get("wrk_2", [])


def test_reversal_blocked_without_appeal_permission(service: FraudService) -> None:
    evaluation = {"riskScoreBps": 7500, "actions": ["quarantine"], "rewardHold": True}
    case = service.open_case_from_evaluation(
        subject_id="wrk_3",
        evaluation=evaluation,
        operator_id="op_fraud",
        reason="golden_trap",
    )
    applied = service.apply_policy_actions(
        case_id=case["caseId"],
        evaluation=evaluation,
        subject_id="wrk_3",
        operator_id="op_fraud",
        reason="enforce",
    )
    action_id = applied[0]["actionId"]
    service.workflow.action_log[action_id].appeal_allowed = False
    with pytest.raises(FraudServiceError) as exc:
        service.workflow.reverse_action(
            case_id=case["caseId"],
            action_id=action_id,
            operator_id="op_appeals",
            reason="attempt",
        )
    assert exc.value.code == "REVERSAL_NOT_PERMITTED"


def test_privacy_deletion_preserves_financial_and_audit_records(service: FraudService) -> None:
    service.minimize_profile(
        subject_id="subj_1",
        payload={"country": "DE", "tier": "T2", "email": "user@example.com", "phone": "+491234"},
    )
    service.privacy.device_links["subj_1"] = [{"accountId": "acc_x", "deviceId": "dev_y"}]
    retained = [
        {"class": "financial_record", "id": "fin_1"},
        {"class": "audit_record", "id": "aud_1"},
        {"class": "marketing_profile", "id": "mkt_1"},
    ]
    result = service.delete_subject_data(subject_id="subj_1", retained_records=retained)
    assert "subj_1" not in service.privacy.profiles
    assert "subj_1" not in service.privacy.device_links
    assert result["preservedRecords"] == 2


def test_velocity_anomaly_detection(service: FraudService) -> None:
    from datetime import UTC, datetime

    now = datetime.now(UTC).isoformat()
    events = [{"name": "claim_attempts", "occurredAt": now} for _ in range(6)]
    velocity = service.evaluate_with_context(signals={}, velocity_events=events)["context"]["velocity"]
    assert velocity["anomalyDetected"] is True
    assert "claim_attempts" in velocity["triggeredRules"]


def test_incident_playbook_returns_steps(service: FraudService) -> None:
    steps = service.incident_playbook("golden_trap_failure")
    assert "quarantine" in steps
    assert "open_case" in steps
