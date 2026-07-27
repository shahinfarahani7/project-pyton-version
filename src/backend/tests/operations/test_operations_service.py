from __future__ import annotations

import pytest
from edgemint.operations.errors import OperationsServiceError
from edgemint.operations.service import OperationsService


@pytest.fixture
def service() -> OperationsService:
    svc = OperationsService()
    svc.seed_catalog()
    return svc


def test_search_views_return_masked_catalog(service: OperationsService) -> None:
    tasks = service.search(view="tasks")
    assert tasks[0]["id"] == "tsk_ops_1"
    workers = service.search(view="workers")
    assert workers[0]["tier"] == "T2"


def test_low_risk_mutation_requires_permission_reason_and_audit(service: OperationsService) -> None:
    receipt = service.submit_mutating_action(
        operator_id="op_1",
        role="operator.standard",
        action="task.requeue",
        resource_id="tsk_ops_1",
        reason_code="incident_response",
        ticket_id="INC-100",
        expected_version=3,
        permission="operations.mutate.low",
    )
    assert receipt["accepted"] is True
    assert len(service.audit_log) == 1
    assert service.audit_log[0].reason_code == "incident_response"


def test_high_risk_action_requires_independent_approval(service: OperationsService) -> None:
    pending = service.submit_mutating_action(
        operator_id="op_1",
        role="operator.standard",
        action="worker.quarantine",
        resource_id="wrk_ops_1",
        reason_code="fraud_investigation",
        ticket_id="FRD-9",
        expected_version=2,
        permission="operations.mutate.low",
    )
    assert pending["status"] == "pending_approval"
    with pytest.raises(OperationsServiceError) as exc:
        service.approve_action(
            approver_id="op_1",
            role="operator.approver",
            approval_id=pending["approvalId"],
        )
    assert exc.value.code == "APPROVAL_SELF_DENIED"
    receipt = service.approve_action(
        approver_id="op_2",
        role="operator.approver",
        approval_id=pending["approvalId"],
    )
    assert receipt["accepted"] is True
    assert len(service.audit_log) >= 1


def test_etag_mismatch_is_rejected(service: OperationsService) -> None:
    with pytest.raises(OperationsServiceError) as exc:
        service.submit_mutating_action(
            operator_id="op_1",
            role="operator.standard",
            action="task.requeue",
            resource_id="tsk_ops_1",
            reason_code="manual_reconciliation",
            ticket_id="REC-1",
            expected_version=99,
            permission="operations.mutate.low",
        )
    assert exc.value.code == "ETAG_MISMATCH"


def test_break_glass_is_time_bound_and_recorded(service: OperationsService) -> None:
    session = service.activate_break_glass(
        operator_id="op_bg",
        role="operator.break_glass",
        reason_code="incident_response",
        ticket_id="INC-999",
    )
    assert session.paged is True
    assert service.break_glass_active(operator_id="op_bg") is not None
    assert any(item.action == "break_glass.activate" for item in service.audit_log)
    assert service.session_recording_hooks


def test_audited_export_masks_sensitive_fields(service: OperationsService) -> None:
    service.catalog["workers"].append(
        {"id": "wrk_sensitive", "status": "active", "email": "ops@example.com", "version": 1},
    )
    export = service.export_audited_view(view="workers", operator_id="op_export")
    worker = next(item for item in export["items"] if item["id"] == "wrk_sensitive")
    assert "@" not in worker["email"]
    assert export["exportId"].startswith("exp_")
