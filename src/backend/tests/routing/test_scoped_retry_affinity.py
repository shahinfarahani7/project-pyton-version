"""T14 audit scenarios: scoped retries, affinity, TaskRun budget (P8-A14 / A14)."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from edgemint.routing.artifact_affinity import (
    artifact_blocks_worker,
    blocked_artifact_digests_from_failures,
)
from edgemint.routing.cloud_fallback import evaluate_cloud_fallback
from edgemint.routing.errors import RouterServiceError
from edgemint.routing.hard_eligibility import evaluate_hard_eligibility
from edgemint.routing.policy import RoutingPolicy
from edgemint.routing.retry_classifier import RetryClass, classify_failure_code
from edgemint.routing.scarcity_cost import AttemptWorkerFailure
from edgemint.routing.task_run_budget import (
    ScopedRetryOutcome,
    TaskRunBudgetLimits,
    TaskRunBudgetUsage,
    assert_task_run_assignment_budget,
    combine_assignment_budget_checks,
    load_task_run_budget_limits,
    resolve_scoped_retry_outcome,
)


def test_t14_permanent_input_error_is_no_retry() -> None:
    assert classify_failure_code("INPUT_SCHEMA_INVALID") == RetryClass.NO_RETRY
    outcome = resolve_scoped_retry_outcome(
        failure_code="INPUT_SCHEMA_INVALID",
        retry_class=RetryClass.NO_RETRY,
        usage=TaskRunBudgetUsage(1, 0, 0),
        limits=TaskRunBudgetLimits(),
        prior_assignments_in_attempt=0,
        max_worker_reassignments=2,
        eligible_workers=3,
        cloud_fallback_permitted=True,
    )
    assert outcome == ScopedRetryOutcome.TERMINAL_NO_RETRY


def test_t14_corrupt_artifact_blocks_worker_pool() -> None:
    failures = [
        AttemptWorkerFailure(
            worker_id="wrk-a",
            failure_code="MODEL_EXECUTION_FAILED",
            observed_at_utc=datetime.now(UTC),
            model_version_id="mdv-corrupt",
        )
    ]
    blocked = blocked_artifact_digests_from_failures(failures)
    assert artifact_blocks_worker(
        model_version_id="mdv-corrupt",
        blocked_artifact_digests=blocked,
    )
    reasons = evaluate_hard_eligibility(
        {
            "featuresBps": {"trust": 10000},
            "heartbeatAgeSeconds": 1,
            "batteryPercent": 100,
            "thermalState": "nominal",
            "modelVersionId": "mdv-corrupt",
            "taskRunFailures": [
                {
                    "workerId": "wrk-a",
                    "failureCode": "MODEL_EXECUTION_FAILED",
                    "observedAtUtc": datetime.now(UTC).isoformat(),
                    "modelVersionId": "mdv-corrupt",
                }
            ],
        }
    )
    assert "ARTIFACT_BLOCKED" in reasons


def test_t14_repeated_thermal_failure_uses_failure_affinity() -> None:
    future = datetime.now(UTC) + timedelta(minutes=5)
    reasons = evaluate_hard_eligibility(
        {
            "featuresBps": {"trust": 10000},
            "heartbeatAgeSeconds": 1,
            "batteryPercent": 100,
            "thermalState": "nominal",
            "workerId": "wrk-hot",
            "attemptFailures": [
                {
                    "workerId": "wrk-hot",
                    "failureCode": "THERMAL_BLOCK",
                    "observedAtUtc": datetime.now(UTC).isoformat(),
                    "cooldownUntilUtc": future.isoformat(),
                }
            ],
        }
    )
    assert "FAILURE_AFFINITY" in reasons


def test_t14_task_run_assignment_budget_not_reset_on_new_attempt() -> None:
    limits = TaskRunBudgetLimits(max_attempts=3, max_total_assignments=4, max_cloud_fallbacks=1)
    exhausted_usage = TaskRunBudgetUsage(attempt_count=2, assignment_count=4, cloud_fallback_count=0)
    with pytest.raises(RouterServiceError) as exc:
        assert_task_run_assignment_budget(usage=exhausted_usage, limits=limits)
    assert exc.value.code == "NO_CAPACITY"
    assert "task_run_assignment_budget_exhausted" in str(exc.value.detail)


def test_t14_no_eligible_worker_considers_new_attempt_before_cloud() -> None:
    limits = TaskRunBudgetLimits(max_attempts=3, max_total_assignments=6, max_cloud_fallbacks=1)
    usage = TaskRunBudgetUsage(attempt_count=1, assignment_count=2, cloud_fallback_count=0)
    outcome = resolve_scoped_retry_outcome(
        failure_code="WORKER_DISCONNECTED",
        retry_class=RetryClass.IMMEDIATE_OTHER_WORKER,
        usage=usage,
        limits=limits,
        prior_assignments_in_attempt=2,
        max_worker_reassignments=2,
        eligible_workers=0,
        cloud_fallback_permitted=True,
    )
    assert outcome == ScopedRetryOutcome.NEW_ATTEMPT


def test_t14_cloud_fallback_respects_task_run_budget() -> None:
    policy = RoutingPolicy.load()
    decision = evaluate_cloud_fallback(
        edge_wait_seconds=float(policy.cloud_after_seconds + 10),
        policy=policy,
        task_run_usage=TaskRunBudgetUsage(attempt_count=2, assignment_count=5, cloud_fallback_count=1),
        task_run_limits=TaskRunBudgetLimits(max_cloud_fallbacks=1),
    )
    assert decision.permitted is False
    assert decision.reason == "task_run_cloud_budget_exhausted"


def test_t14_exhausted_attempt_and_budget_is_terminal() -> None:
    limits = TaskRunBudgetLimits(max_attempts=2, max_total_assignments=3, max_cloud_fallbacks=0)
    usage = TaskRunBudgetUsage(attempt_count=2, assignment_count=3, cloud_fallback_count=0)
    outcome = resolve_scoped_retry_outcome(
        failure_code="RUNTIME_OUT_OF_MEMORY",
        retry_class=RetryClass.STRONGER_WORKER,
        usage=usage,
        limits=limits,
        prior_assignments_in_attempt=3,
        max_worker_reassignments=2,
        eligible_workers=0,
        cloud_fallback_permitted=False,
    )
    assert outcome == ScopedRetryOutcome.TERMINAL_BUDGET_EXHAUSTED


def test_t14_combine_checks_enforces_per_attempt_and_task_run() -> None:
    with pytest.raises(RouterServiceError) as exc:
        combine_assignment_budget_checks(
            prior_assignments_in_attempt=3,
            max_worker_reassignments=2,
            task_run_usage=TaskRunBudgetUsage(1, 1, 0),
            task_run_limits=TaskRunBudgetLimits(),
        )
    assert exc.value.code == "NO_CAPACITY"


def test_task_run_budget_limits_loaded_from_policy() -> None:
    limits = load_task_run_budget_limits()
    assert limits.max_attempts == 3
    assert limits.max_total_assignments == 6
