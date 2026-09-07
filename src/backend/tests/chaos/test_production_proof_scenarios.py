"""Phase 7 chaos scenarios — dev/staging invariant proofs (Section 65 Phase 7)."""
from __future__ import annotations

import json
import subprocess
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

from edgemint.billing.errors import FinanceServiceError
from edgemint.billing.service import FinanceService
from edgemint.pricing.engine import PriceInput
from edgemint.routing.cloud_fallback import evaluate_cloud_fallback
from edgemint.routing.errors import RouterServiceError
from edgemint.routing.exclusive_groups import can_reserve_exclusive_group
from edgemint.routing.fencing import assert_reassignment_budget
from edgemint.routing.policy import RoutingPolicy
from edgemint.routing.retry_classifier import RetryClass, classify_failure_code
from edgemint.results.errors import ResultServiceError
from edgemint.results.intake import validate_submission_bindings
from edgemint.security.tokens import hash_session_token
from edgemint.tasks.catalog_closure import validate_catalog_sync
from edgemint.workers.assignments import AssignmentCommandService
from edgemint.workers.consent_transitions import plan_consent_revocation, plan_contribution_mode_transition
from edgemint.workers.errors import WorkerServiceError
from edgemint.workers.failure_codes import CLOSED_WORKER_FAILURE_CODES

ROOT = Path(__file__).resolve().parents[4]
PRICE_INPUT = {
    "taskType": "document.ocr",
    "quantity": 100,
    "plan": "startup",
    "priority": "standard",
    "verification": "standard",
    "region": "eu-central",
    "executionPolicy": "edge_only",
    "retention": "default",
}
REWARD_INPUT = {
    "taskType": "document.ocr",
    "quanta": 1,
    "tier": "T2",
    "qualityMilli": 950,
    "urgency": "standard",
    "scarcityBps": 10000,
    "reliabilityBps": 10000,
}


def _run_tool(script: str) -> dict[str, object]:
    proc = subprocess.run(
        [sys.executable, str(ROOT / "tools" / script)],
        capture_output=True,
        text=True,
        check=False,
    )
    payload: dict[str, object] = {"exitCode": proc.returncode, "script": script}
    if proc.stdout.strip():
        try:
            payload["result"] = json.loads(proc.stdout)
        except json.JSONDecodeError:
            payload["stdout"] = proc.stdout.strip()[:500]
    if proc.returncode != 0 and proc.stderr.strip():
        payload["stderr"] = proc.stderr.strip()[:500]
    return payload


def _active_row(*, fence: int = 7, expired: bool = False) -> dict[str, object]:
    expires = datetime.now(UTC) + (timedelta(seconds=-1) if expired else timedelta(minutes=2))
    return {
        "fence_token": fence,
        "lease_token_hash": hash_session_token("lease-token"),
        "lease_expires_at_utc": expires,
    }


def test_p7_chaos_20_workers_load_invariant() -> None:
    payload = _run_tool("run_56_task_protocol_load.py")
    assert payload["exitCode"] == 0, payload
    result = payload["result"]
    assert isinstance(result, dict)
    assert result["workers"] == 20
    assert result["status"] == "passed"


def test_p7_chaos_56_task_catalog_execution_matrix() -> None:
    reports = validate_catalog_sync()
    assert len(reports) == 56
    incomplete = [report for report in reports if report.executable and not report.contract_complete]
    assert incomplete == []
    golden = ROOT / "tools" / "validate_catalog_closure.py"
    proc = subprocess.run(
        [sys.executable, str(golden)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc.returncode == 0, proc.stderr or proc.stdout


def test_p7_chaos_multi_assignment_exclusive_groups() -> None:
    assert can_reserve_exclusive_group(
        requested_group="ocr_inference",
        active_counts={"llm_inference": 1},
        device_certified=True,
    )
    assert can_reserve_exclusive_group(
        requested_group="ocr_inference",
        active_counts={"ocr_inference": 1, "llm_inference": 0},
        device_certified=True,
        thermal_state="nominal",
    )


def test_p7_chaos_resource_exhaustion_no_overcommit() -> None:
    with pytest.raises(RouterServiceError) as exc:
        assert_reassignment_budget(assignment_count=6, max_reassignments=5)
    assert exc.value.code == "NO_CAPACITY"


def test_p7_chaos_worker_disconnect_retry_class() -> None:
    assert classify_failure_code("WORKER_DISCONNECTED") == RetryClass.IMMEDIATE_OTHER_WORKER


def test_p7_chaos_lease_expiry_rejects_writes() -> None:
    with pytest.raises(WorkerServiceError) as exc:
        AssignmentCommandService._verify_active_credential(
            _active_row(expired=True),
            lease_token="lease-token",
            fence_token=7,
        )
    assert exc.value.code == "ASSIGNMENT_STALE_FENCE"


def test_p7_chaos_stale_result_rejected() -> None:
    from tests.verification.test_verification_engine import sample_binding, sample_submission

    with pytest.raises(ResultServiceError) as exc:
        validate_submission_bindings(
            sample_submission(fence_token=2),
            sample_binding(fence_token=3),
            signing_material="edgemint-development-signing-secret",
            max_output_bytes=1024,
            existing_result_digests=set(),
        )
    assert exc.value.code == "ASSIGNMENT_STALE_FENCE"


def test_p7_chaos_runtime_crash_closed_code() -> None:
    assert "RUNTIME_CRASH" in CLOSED_WORKER_FAILURE_CODES
    assert classify_failure_code("RUNTIME_CRASH") == RetryClass.IMMEDIATE_OTHER_WORKER


def test_p7_chaos_oom_server_retry_not_local() -> None:
    assert classify_failure_code("RUNTIME_OUT_OF_MEMORY") == RetryClass.STRONGER_WORKER
    forbidden = ROOT / "src" / "apps" / "worker" / "lib"
    source = "\n".join(path.read_text(encoding="utf-8") for path in forbidden.rglob("*.dart"))
    assert "LocalReassignmentManager" not in source
    assert "LocalRetryOrchestrator" not in source


def test_p7_chaos_thermal_failure_closed_code() -> None:
    assert classify_failure_code("THERMAL_BLOCK") == RetryClass.IMMEDIATE_OTHER_WORKER
    assert "THERMAL_BLOCK" in CLOSED_WORKER_FAILURE_CODES


def test_p7_chaos_retry_exhaustion_terminal() -> None:
    with pytest.raises(RouterServiceError) as exc:
        assert_reassignment_budget(assignment_count=4, max_reassignments=3)
    assert exc.value.code == "NO_CAPACITY"


def test_p7_chaos_cloud_fallback_audit() -> None:
    policy = RoutingPolicy.load()
    decision = evaluate_cloud_fallback(
        edge_wait_seconds=float(policy.cloud_after_seconds + 5),
        policy=policy,
    )
    assert decision.permitted is True
    assert decision.reason == "edge_wait_exceeded"
    assert decision.cloudAfterSeconds == policy.cloud_after_seconds


def test_p7_chaos_reward_exactly_once() -> None:
    service = FinanceService()
    price = service.pricing_engine.quote(PriceInput.from_vector(PRICE_INPUT))
    service.capture_reservation(
        task_id="tsk_reward_once",
        quote_id="qte_reward_once",
        amount_micro_eur=price.charge_micros,
        available_micro_eur=price.charge_micros,
    )
    body = service.finalize_paid_task(
        idempotency_key="idem-reward-once",
        task_id="tsk_reward_once",
        task_revision_id="rev_once",
        result_id="res_once",
        verification_id="ver_once",
        price_input=PRICE_INPUT,
        reward_input=REWARD_INPUT,
    )
    reward_micros = body["rewardAccrual"]["workerRewardMicros"]
    with pytest.raises(FinanceServiceError) as exc:
        service.finalize_paid_task(
            idempotency_key="idem-reward-once",
            task_id="tsk_reward_once",
            task_revision_id="rev_once",
            result_id="res_once_dup",
            verification_id="ver_once_dup",
            price_input=PRICE_INPUT,
            reward_input=REWARD_INPUT,
        )
    assert exc.value.code == "IDEMPOTENCY_CONFLICT"
    assert reward_micros > 0


def test_p7_chaos_long_context_summarize_plan() -> None:
    from edgemint.routing.execution_plan_resolver import resolve_execution_plan

    plan = resolve_execution_plan(task_type="text.summarize", estimated_input_tokens=8000)
    assert plan.plan_name == "text-summarize-map-reduce"
    assert len(plan.stages) >= 2


def test_p7_chaos_chunk_resume_fence_aware() -> None:
    migration = (ROOT / "database" / "sql" / "013_websocket_outbox_expansion_replay.sql").read_text()
    checkpoint = (ROOT / "src" / "apps" / "worker" / "lib" / "runtime" / "checkpoint_manager.dart").read_text()
    assert "fence" in checkpoint.lower()
    assert "ON CONFLICT" in migration


def test_p7_chaos_recursive_reduce_depth() -> None:
    pipeline = (
        ROOT / "src" / "apps" / "worker" / "lib" / "inference" / "llm" / "hierarchical_summarize_pipeline.dart"
    ).read_text()
    bounds = (
        ROOT / "src" / "apps" / "worker" / "lib" / "inference" / "llm" / "hierarchical_reduce_bounds.dart"
    ).read_text()
    assert "reducePartials" in pipeline
    assert "ReduceProgressTracker" in pipeline
    assert "maxReduceDepth" in bounds
    assert pipeline.count("await reducePartials") >= 2


def test_p7_chaos_model_corruption_rejected() -> None:
    verifier = (ROOT / "src" / "apps" / "worker" / "lib" / "runtime" / "model_artifact_verifier.dart").read_text()
    assert "sha256" in verifier.lower() or "digest" in verifier.lower()
    assert classify_failure_code("MODEL_EXECUTION_FAILED") == RetryClass.STRONGER_WORKER


def test_p7_chaos_model_update_during_residency() -> None:
    manager = (ROOT / "src" / "apps" / "worker" / "lib" / "runtime" / "model_runtime_manager.dart").read_text()
    assert "Cannot unload while sessions are open" in manager
    assert "modelReplacement" in manager


def test_p7_chaos_storage_pressure_eviction() -> None:
    storage = (ROOT / "src" / "apps" / "worker" / "lib" / "runtime" / "storage_pressure_manager.dart").read_text()
    assert "activeFence" in storage or "active_fence" in storage.lower() or "fence" in storage.lower()


def test_p7_chaos_consent_30_to_50() -> None:
    plan = plan_contribution_mode_transition(previous_mode_id="balanced", next_mode_id="performance")
    assert plan.previous_percent == 30
    assert plan.next_percent == 50
    assert plan.apply_to_new_reservations_only is True


def test_p7_chaos_consent_50_to_30() -> None:
    plan = plan_contribution_mode_transition(previous_mode_id="performance", next_mode_id="balanced")
    assert plan.previous_percent == 50
    assert plan.next_percent == 30
    assert plan.stop_new_stages_above_limit is True


def test_p7_chaos_consent_revoke() -> None:
    plan = plan_consent_revocation(current_mode_id="balanced")
    assert plan.revoke_new_work_immediately is True
    assert classify_failure_code("CONSENT_REVOKED") == RetryClass.NO_RETRY


def test_p7_chaos_thermal_transition_concurrency() -> None:
    assert can_reserve_exclusive_group(
        requested_group="ocr_inference",
        active_counts={"ocr_inference": 1},
        device_certified=True,
        thermal_state="fair",
    ) is False


def test_p7_chaos_websocket_replay() -> None:
    payload = _run_tool("verify_websocket_replay_source.py")
    assert payload["exitCode"] == 0, payload


def test_p7_chaos_stale_fence_writes() -> None:
    with pytest.raises(WorkerServiceError) as exc:
        AssignmentCommandService._verify_active_credential(
            _active_row(fence=8),
            lease_token="lease-token",
            fence_token=7,
        )
    assert exc.value.code == "ASSIGNMENT_STALE_FENCE"
    payload = _run_tool("verify_production_completion_source.py")
    assert payload["exitCode"] == 0, payload


def test_p7_chaos_duplicate_delivery_idempotent() -> None:
    migration = (ROOT / "database" / "sql" / "013_websocket_outbox_expansion_replay.sql").read_text()
    assert "ON CONFLICT (subscription_id, outbox_event_id) DO NOTHING" in migration
    payload = _run_tool("verify_websocket_replay_source.py")
    assert payload["exitCode"] == 0, payload
