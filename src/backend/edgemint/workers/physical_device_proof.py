"""Physical-device process lifecycle proof matrix (Architecture v2 A17 / T17)."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

DEFAULT_POLICY_PATH = (
    Path(__file__).resolve().parents[4]
    / "dsl"
    / "policies"
    / "worker"
    / "android-process-lifecycle-v1.yaml"
)


@dataclass(frozen=True)
class PhysicalDeviceMatrixEntry:
    scenario_id: str
    title: str
    requires_physical_device: bool
    emulator_sufficient: bool = False


REQUIRED_T17_SCENARIOS: tuple[PhysicalDeviceMatrixEntry, ...] = (
    PhysicalDeviceMatrixEntry(
        scenario_id="background_fgs",
        title="Assignment runs under visible foreground service while app backgrounded",
        requires_physical_device=True,
    ),
    PhysicalDeviceMatrixEntry(
        scenario_id="app_suspend",
        title="Platform suspension invalidates in-flight native session; safe cleanup",
        requires_physical_device=True,
    ),
    PhysicalDeviceMatrixEntry(
        scenario_id="process_death",
        title="Process kill drops native handles; no stale resume without fresh grant",
        requires_physical_device=True,
    ),
    PhysicalDeviceMatrixEntry(
        scenario_id="device_reboot",
        title="Cold boot reconciles installed artifact vs invalidated runtime generation",
        requires_physical_device=True,
    ),
    PhysicalDeviceMatrixEntry(
        scenario_id="os_memory_pressure",
        title="OS memory pressure triggers lifecycle shutdown without corruption",
        requires_physical_device=True,
    ),
    PhysicalDeviceMatrixEntry(
        scenario_id="emulator_smoke_comparison",
        title="Emulator smoke only; records divergence from physical baseline",
        requires_physical_device=False,
        emulator_sufficient=True,
    ),
)


def load_android_process_lifecycle_policy(
    path: Path | None = None,
) -> dict[str, Any]:
    policy_path = path or DEFAULT_POLICY_PATH
    raw = yaml.safe_load(policy_path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError(f"invalid lifecycle policy document: {policy_path}")
    return raw


def matrix_entries_from_policy(policy: dict[str, Any]) -> list[PhysicalDeviceMatrixEntry]:
    matrix = policy.get("physicalDeviceMatrix") or {}
    entries: list[PhysicalDeviceMatrixEntry] = []
    for row in matrix.get("requiredScenarios") or []:
        if not isinstance(row, dict):
            continue
        entries.append(
            PhysicalDeviceMatrixEntry(
                scenario_id=str(row.get("id", "")),
                title=str(row.get("title", "")),
                requires_physical_device=bool(row.get("requiresPhysicalDevice", True)),
                emulator_sufficient=bool(row.get("emulatorSufficient", False)),
            )
        )
    return entries


def evaluate_t17_certification(
    *,
    device_is_emulator: bool,
    scenarios_passed: set[str],
    policy: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Return certification status for T17 matrix coverage."""
    loaded = policy or load_android_process_lifecycle_policy()
    matrix = matrix_entries_from_policy(loaded) or list(REQUIRED_T17_SCENARIOS)
    physical_required = {
        entry.scenario_id
        for entry in matrix
        if entry.requires_physical_device and not entry.emulator_sufficient
    }
    emulator_only = {
        entry.scenario_id for entry in matrix if entry.emulator_sufficient
    }

    physical_passed = physical_required & scenarios_passed
    emulator_passed = emulator_only & scenarios_passed

    if device_is_emulator:
        production_certified = False
        classification = "IMPLEMENTED_DEV_ONLY"
        gaps = sorted(physical_required - scenarios_passed)
    else:
        production_certified = physical_required <= scenarios_passed
        classification = (
            "IMPLEMENTED_PRODUCTION" if production_certified else "IMPLEMENTED_DEV_ONLY"
        )
        gaps = sorted(physical_required - scenarios_passed)

    return {
        "deviceIsEmulator": device_is_emulator,
        "emulatorAloneCannotCertifyProduction": bool(
            (loaded.get("physicalDeviceMatrix") or {}).get(
                "emulatorAloneCannotCertifyProduction", True
            )
        ),
        "requiredPhysicalScenarios": sorted(physical_required),
        "physicalScenariosPassed": sorted(physical_passed),
        "emulatorScenariosPassed": sorted(emulator_passed),
        "productionCertified": production_certified,
        "classification": classification,
        "gaps": gaps,
    }


def reconcile_with_p7_load_sim(*, p7_evidence_status: str) -> dict[str, str]:
    """T17 complements but does not replace P7 20-worker load sim."""
    return {
        "p7LoadSimRole": "complements_t17",
        "p7EvidenceStatus": p7_evidence_status,
        "note": (
            "P7-CHAOS-20-workers proves dev/staging load invariants; "
            "T17 requires named physical-device lifecycle matrix."
        ),
    }
