from edgemint.routing.task_manager_load_scenario import (
    assert_invariants,
    run_scenario,
)


def test_five_hundred_tasks_respect_device_limits_and_stay_queued() -> None:
    report = run_scenario()

    assert len(report.devices) == 100
    assert len(report.tasks) == 500
    assert len(report.assignments) + len(report.queued) == 500
    assert_invariants(report)


def test_heavy_tasks_land_on_the_strongest_tied_tier() -> None:
    report = run_scenario()

    heavy = [item for item in report.assignments if item.heavy]
    assert heavy
    assert all(item.tier == item.strongest_tied_tier for item in heavy)
    assert all(item.tier in {"T3", "T4"} for item in heavy)
    assert all(item.tier == "T4" for item in heavy if item.runtime == "vlm_runtime")


def test_assignment_order_is_deterministic() -> None:
    first = [(item.task_id, item.worker_id) for item in run_scenario().placements]
    second = [(item.task_id, item.worker_id) for item in run_scenario().placements]

    assert first == second
