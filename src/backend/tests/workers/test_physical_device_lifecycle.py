"""T17 audit scenarios: physical-device process lifecycle proof (P8-A17 / A17)."""

from __future__ import annotations

from edgemint.workers.physical_device_proof import (
    REQUIRED_T17_SCENARIOS,
    evaluate_t17_certification,
    load_android_process_lifecycle_policy,
    matrix_entries_from_policy,
    reconcile_with_p7_load_sim,
)


def test_t17_policy_declares_physical_matrix_and_fgs_profile() -> None:
    policy = load_android_process_lifecycle_policy()
    assert policy["platform"] == "android"
    assert policy["foregroundExecution"]["serviceClass"] == "ExecutionForegroundService"
    matrix = matrix_entries_from_policy(policy)
    assert len(matrix) == len(REQUIRED_T17_SCENARIOS)
    physical = [entry for entry in matrix if entry.requires_physical_device]
    assert len(physical) == 5
    assert policy["physicalDeviceMatrix"]["emulatorAloneCannotCertifyProduction"] is True


def test_t17_emulator_cannot_certify_production_without_physical_scenarios() -> None:
    evaluation = evaluate_t17_certification(
        device_is_emulator=True,
        scenarios_passed={"emulator_smoke_comparison"},
    )
    assert evaluation["productionCertified"] is False
    assert evaluation["classification"] == "IMPLEMENTED_DEV_ONLY"
    assert "process_death" in evaluation["gaps"]


def test_t17_physical_device_matrix_passes_when_all_required_scenarios_done() -> None:
    required = {entry.scenario_id for entry in REQUIRED_T17_SCENARIOS if entry.requires_physical_device}
    evaluation = evaluate_t17_certification(
        device_is_emulator=False,
        scenarios_passed=required | {"emulator_smoke_comparison"},
    )
    assert evaluation["productionCertified"] is True
    assert evaluation["classification"] == "IMPLEMENTED_PRODUCTION"
    assert evaluation["gaps"] == []


def test_t17_complements_p7_load_sim_without_replacing_it() -> None:
    note = reconcile_with_p7_load_sim(p7_evidence_status="passed")
    assert note["p7LoadSimRole"] == "complements_t17"
    assert "T17" in note["note"]
