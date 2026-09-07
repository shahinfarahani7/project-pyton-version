"""T19 audit scenarios: DRR fairness, backpressure and operating signals (P8-A19 / A19)."""

from __future__ import annotations

from datetime import UTC, datetime

from edgemint.routing.admission_backpressure import (
    BackpressureReason,
    PipelinePressureSnapshot,
    evaluate_admission_backpressure,
    evaluate_pipeline_backpressure,
    evaluate_queue_admission,
)
from edgemint.routing.fair_queue import rank_task_attempts
from edgemint.routing.operating_signals import collect_operating_signals, reveal_primary_blocker
from edgemint.routing.service import RouterService
from edgemint.routing.workspace_drr import (
    WorkspaceDrrState,
    apply_dispatch_debit,
    attach_workspace_deficits,
    compute_queue_cost_units,
    credit_idle_workspaces,
    enforce_consecutive_assignment_cap,
    load_admission_backpressure_policy,
    select_next_workspace_under_drr,
)


def _attempt(**overrides: object) -> dict[str, object]:
    base: dict[str, object] = {
        "attemptId": "att_base",
        "workspaceId": "ws_1",
        "priorityBps": 2000,
        "submittedAt": datetime(2026, 9, 1, 10, 0, tzinfo=UTC),
        "deadlineAt": None,
        "taskId": "tsk_base",
        "deficitUnits": 0,
        "waitingSeconds": 0,
    }
    base.update(overrides)
    return base


def test_t19_policy_declares_drr_caps_and_distinct_blocked_states() -> None:
    policy = load_admission_backpressure_policy()
    assert policy["drr"]["algorithm"] == "workspace_deficit_round_robin"
    assert policy["workspaceCaps"]["maxQueuedTasksPerWorkspace"] == 500
    states = set(policy["distinctBlockedStates"])
    assert BackpressureReason.NO_ELIGIBLE_WORKER.value in states
    assert BackpressureReason.VALIDATION_BACKPRESSURE.value in states


def test_t19_large_job_cost_does_not_permanently_starve_small_workspace() -> None:
    state = WorkspaceDrrState()
    credit_idle_workspaces(state, ["ws_small", "ws_large"], quantum_units=1, credit_cap_units=20)
    large_cost = compute_queue_cost_units(120_000)
    apply_dispatch_debit(state, workspace_id="ws_large", cost_units=large_cost)
    credit_idle_workspaces(state, ["ws_small"], quantum_units=5, credit_cap_units=20)

    attempts = [
        _attempt(attemptId="att_large", workspaceId="ws_large", taskId="tsk_large", waitingSeconds=5),
        _attempt(attemptId="att_small", workspaceId="ws_small", taskId="tsk_small", waitingSeconds=5),
    ]
    enriched = attach_workspace_deficits(attempts, state)
    ordered = rank_task_attempts(enriched)
    assert ordered[0] == "att_small"


def test_t19_consecutive_assignment_cap_blocks_workspace_monopoly() -> None:
    state = WorkspaceDrrState()
    state.consecutive_assignments["ws_a"] = 5
    assert enforce_consecutive_assignment_cap(state, workspace_id="ws_a", max_consecutive=5) is False
    selected = select_next_workspace_under_drr(
        [
            _attempt(workspaceId="ws_a", attemptId="att_a"),
            _attempt(workspaceId="ws_b", attemptId="att_b"),
        ],
        state,
        max_consecutive=5,
    )
    assert selected == "ws_b"


def test_t19_queue_and_pipeline_backpressure_use_distinct_reasons() -> None:
    policy = load_admission_backpressure_policy()
    queue = evaluate_queue_admission(
        workspace_id="ws_x",
        queued_count=500,
        active_count=1,
        input_cost_units=10,
        policy=policy,
    )
    assert queue.reason_code == BackpressureReason.ADMISSION_LIMIT_EXCEEDED

    pipeline = evaluate_pipeline_backpressure(
        PipelinePressureSnapshot(validation_backlog=512),
        policy=policy,
    )
    assert pipeline.reason_code == BackpressureReason.VALIDATION_BACKPRESSURE

    combined = evaluate_admission_backpressure(
        workspace_id="ws_x",
        queued_count=1,
        active_count=1,
        input_cost_units=10,
        pipeline=PipelinePressureSnapshot(upload_in_flight=256),
        policy=policy,
    )
    assert combined.reason_code == BackpressureReason.UPLOAD_BACKPRESSURE


def test_t19_operating_signals_reveal_starvation_blocker() -> None:
    state = WorkspaceDrrState()
    state.set_deficit("ws_starved", 3)
    attempts = [
        {
            "workspaceId": "ws_starved",
            "deficitUnits": 3,
            "waitingSeconds": 650,
            "starvationLimitSeconds": 300,
        }
    ]
    signals = collect_operating_signals(
        attempts=attempts,
        drr_state=state,
        pipeline=PipelinePressureSnapshot(),
    )
    assert signals[0]["starvedTaskCount"] == 1
    assert reveal_primary_blocker(signals) == "STARVATION_RISK"


def test_t19_router_service_hooks_expose_cost_admission_and_signals() -> None:
    router = RouterService()
    assert router.compute_queue_cost_units(2500) == 3
    admission = router.evaluate_admission_backpressure(
        workspace_id="ws_y",
        queued_count=600,
        active_count=1,
        input_cost_units=10,
    )
    assert admission["permitted"] is False
    assert admission["reasonCode"] == BackpressureReason.ADMISSION_LIMIT_EXCEEDED.value
    assert admission["boundedWaitSeconds"] == 300

    signals = router.collect_operating_signals(
        attempts=[_attempt(workspaceId="ws_y", waitingSeconds=120)],
        admission_blocked_reason=BackpressureReason.ADMISSION_LIMIT_EXCEEDED.value,
    )
    assert signals[0]["blockedReason"] == BackpressureReason.ADMISSION_LIMIT_EXCEEDED.value
