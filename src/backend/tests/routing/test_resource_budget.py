from __future__ import annotations

from edgemint.routing.resource_budget import (
    CONTRIBUTION_BUDGET_MULTIPLIERS_BPS,
    apply_contribution_budget,
    contribution_budget_multiplier_bps,
    contribution_budget_multiplier_bps_for_mode,
)
from edgemint.routing.service import RouterService


def test_contribution_multipliers_match_30_and_50_percent() -> None:
    assert CONTRIBUTION_BUDGET_MULTIPLIERS_BPS["balanced"] == 3000
    assert CONTRIBUTION_BUDGET_MULTIPLIERS_BPS["performance"] == 5000
    assert contribution_budget_multiplier_bps_for_mode("balanced") == 3000
    assert contribution_budget_multiplier_bps_for_mode("performance") == 5000
    assert contribution_budget_multiplier_bps(approved_percent=30) == 3000
    assert contribution_budget_multiplier_bps(approved_percent=50) == 5000


def test_apply_contribution_budget_scales_capacity() -> None:
    assert apply_contribution_budget(capacity_units=10_000, budget_multiplier_bps=3000) == 3000
    assert apply_contribution_budget(capacity_units=10_000, budget_multiplier_bps=5000) == 5000


def test_router_service_effective_cpu_budget_hook() -> None:
    router = RouterService()
    assert router.effective_cpu_budget_units(device_cpu_capacity=10_000, budget_multiplier_bps=3000) == 3000
    assert router.effective_cpu_budget_units(device_cpu_capacity=10_000, budget_multiplier_bps=5000) == 5000
