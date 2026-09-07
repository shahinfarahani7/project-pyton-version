from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from edgemint.routing.errors import router_error
from edgemint.routing.policy import RoutingPolicy
from edgemint.routing.retry_classifier import RetryClass


@dataclass(frozen=True, slots=True)
class TaskRunBudgetLimits:
    max_attempts: int = 3
    max_total_assignments: int = 6
    max_cloud_fallbacks: int = 1


@dataclass(frozen=True, slots=True)
class TaskRunBudgetUsage:
    attempt_count: int
    assignment_count: int
    cloud_fallback_count: int


class ScopedRetryOutcome(StrEnum):
    RETRY_SAME_ATTEMPT = "retry_same_attempt"
    NEW_ATTEMPT = "new_attempt"
    CLOUD_FALLBACK = "cloud_fallback"
    TERMINAL_NO_RETRY = "terminal_no_retry"
    TERMINAL_BUDGET_EXHAUSTED = "terminal_budget_exhausted"


def load_task_run_budget_limits(policy: RoutingPolicy | None = None) -> TaskRunBudgetLimits:
    active = policy or RoutingPolicy.load()
    raw = active.spec.get("taskRunBudget") or {}
    return TaskRunBudgetLimits(
        max_attempts=int(raw.get("maxAttempts", 3)),
        max_total_assignments=int(raw.get("maxTotalAssignments", 6)),
        max_cloud_fallbacks=int(raw.get("maxCloudFallbacks", 1)),
    )


def assert_task_run_assignment_budget(
    *,
    usage: TaskRunBudgetUsage,
    limits: TaskRunBudgetLimits,
) -> None:
    if usage.assignment_count >= limits.max_total_assignments:
        raise router_error(
            "NO_CAPACITY",
            detail="task_run_assignment_budget_exhausted",
        )


def evaluate_new_attempt_permitted(
    *,
    usage: TaskRunBudgetUsage,
    limits: TaskRunBudgetLimits,
    retry_class: RetryClass,
) -> bool:
    if retry_class == RetryClass.NO_RETRY:
        return False
    return usage.attempt_count < limits.max_attempts


def cloud_fallback_budget_permitted(
    *,
    usage: TaskRunBudgetUsage,
    limits: TaskRunBudgetLimits,
) -> bool:
    return usage.cloud_fallback_count < limits.max_cloud_fallbacks


def resolve_scoped_retry_outcome(
    *,
    failure_code: str,
    retry_class: RetryClass,
    usage: TaskRunBudgetUsage,
    limits: TaskRunBudgetLimits,
    prior_assignments_in_attempt: int,
    max_worker_reassignments: int,
    eligible_workers: int,
    cloud_fallback_permitted: bool,
) -> ScopedRetryOutcome:
    if retry_class == RetryClass.NO_RETRY:
        return ScopedRetryOutcome.TERMINAL_NO_RETRY

    if eligible_workers == 0:
        if evaluate_new_attempt_permitted(
            usage=usage,
            limits=limits,
            retry_class=retry_class,
        ):
            return ScopedRetryOutcome.NEW_ATTEMPT
        if cloud_fallback_permitted and cloud_fallback_budget_permitted(
            usage=usage,
            limits=limits,
        ):
            return ScopedRetryOutcome.CLOUD_FALLBACK
        return ScopedRetryOutcome.TERMINAL_BUDGET_EXHAUSTED

    if prior_assignments_in_attempt <= max_worker_reassignments:
        if usage.assignment_count < limits.max_total_assignments:
            return ScopedRetryOutcome.RETRY_SAME_ATTEMPT

    if evaluate_new_attempt_permitted(
        usage=usage,
        limits=limits,
        retry_class=retry_class,
    ):
        return ScopedRetryOutcome.NEW_ATTEMPT

    if cloud_fallback_permitted and cloud_fallback_budget_permitted(
        usage=usage,
        limits=limits,
    ):
        return ScopedRetryOutcome.CLOUD_FALLBACK

    return ScopedRetryOutcome.TERMINAL_BUDGET_EXHAUSTED


def combine_assignment_budget_checks(
    *,
    prior_assignments_in_attempt: int,
    max_worker_reassignments: int,
    task_run_usage: TaskRunBudgetUsage,
    task_run_limits: TaskRunBudgetLimits,
) -> None:
    """Per-attempt reassignment plus TaskRun-wide assignment budget (v2 §1436)."""
    if prior_assignments_in_attempt > max_worker_reassignments:
        raise router_error("NO_CAPACITY", detail="attempt_reassignment_budget_exhausted")
    assert_task_run_assignment_budget(usage=task_run_usage, limits=task_run_limits)
