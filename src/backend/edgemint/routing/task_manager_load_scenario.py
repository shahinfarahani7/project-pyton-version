"""Deterministic 100-device / 500-task assignment scenario.

Drives the production ranker (:class:`edgemint.routing.service.RouterService`) and the
production CPU, memory, storage, tier and runtime filters. Two extra caps from this
scenario sit on top:

* reserved memory stays at or below 70% of the device's total RAM
* a device holds at most one heavy task (minimum device tier T3 or T4)

Tasks that fit no device stay queued. Nothing is dropped. This module does not open a
database and does not replace the live assignment transaction.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta

from edgemint.routing.fencing import QueueAttempt, rank_queue_attempts, tier_capacity
from edgemint.routing.resource_budget import (
    EffectiveResourceBudgets,
    compute_effective_resource_budgets,
    contribution_budget_multiplier_bps,
)
from edgemint.routing.runtime_compatibility import load_active_runtime_compatibility_profile
from edgemint.routing.service import RouterService
from edgemint.workers.device_capability import (
    BatterySpec,
    DeviceCapabilityReport,
    MemorySpec,
    NetworkSpec,
    PlatformSpec,
    ResourceVector,
    StorageSpec,
    ThermalSpec,
)

_GIB = 1024**3
_MIB = 1024**2
_RAM_CEILING_PERCENT = 70
_HEAVY_TIER_RANK = 3
_TIER_RANK = {"T1": 1, "T2": 2, "T3": 3, "T4": 4}
_CONTRIBUTION_BPS = contribution_budget_multiplier_bps(approved_percent=50)
_DEVICE_PLAN = (
    ("T1", 40, 4_000, 4 * _GIB),
    ("T2", 30, 8_000, 6 * _GIB),
    ("T3", 20, 16_000, 8 * _GIB),
    ("T4", 10, 32_000, 12 * _GIB),
)
_TASK_PLAN = (
    ("system", 250, 400, 256 * _MIB, 1_000),
    ("paddle_ocr", 150, 1_500, 768 * _MIB, 4_000),
    ("mediapipe_llm", 70, 5_000, 2 * _GIB, 7_000),
    ("vlm_runtime", 30, 12_000, 4 * _GIB, 9_000),
)
_RUNTIME_BY_TIER = {
    "T1": ("system", "network_io"),
    "T2": ("paddle_ocr", "image_classifier", "object_detector", "embedding_runtime"),
    "T3": ("mediapipe_llm", "segmentation_runtime"),
    "T4": ("vlm_runtime",),
}
_STORAGE_REQUEST = 64 * _MIB
_BASE_TIME = datetime(2026, 11, 1, tzinfo=UTC)


@dataclass
class DeviceState:
    worker_id: str
    tier: str
    total_ram: int
    budgets: EffectiveResourceBudgets
    runtimes: tuple[str, ...]
    reserved_cpu: int = 0
    reserved_memory: int = 0
    reserved_storage: int = 0
    leases: list[str] = field(default_factory=list)

    @property
    def heavy_leases(self) -> int:
        return sum(1 for runtime in self.leases if is_heavy(runtime))


@dataclass(frozen=True, slots=True)
class ScenarioTask:
    task_id: str
    runtime: str
    cpu_units: int
    memory_bytes: int
    priority_bps: int
    submitted_at: datetime

    @property
    def heavy(self) -> bool:
        return is_heavy(self.runtime)


@dataclass(frozen=True, slots=True)
class Placement:
    task_id: str
    runtime: str
    heavy: bool
    worker_id: str | None
    tier: str | None
    score: int | None
    best_score: int | None
    strongest_tied_tier: str | None


@dataclass
class ScenarioReport:
    devices: list[DeviceState]
    tasks: list[ScenarioTask]
    placements: list[Placement]

    @property
    def assignments(self) -> list[Placement]:
        return [item for item in self.placements if item.worker_id is not None]

    @property
    def queued(self) -> list[Placement]:
        return [item for item in self.placements if item.worker_id is None]


def is_heavy(runtime: str) -> bool:
    requirement = load_active_runtime_compatibility_profile().task_requirements[runtime]
    minimum = requirement.minimum_device_tier
    return minimum is not None and _TIER_RANK[minimum] >= _HEAVY_TIER_RANK


def _runtimes_for(tier: str) -> tuple[str, ...]:
    collected: list[str] = []
    for name in ("T1", "T2", "T3", "T4"):
        collected.extend(_RUNTIME_BY_TIER[name])
        if name == tier:
            break
    return tuple(collected)


def _budgets_for(tier: str, cpu_units: int, total_ram: int) -> EffectiveResourceBudgets:
    capability = DeviceCapabilityReport(
        platform=PlatformSpec(os="android", abi="arm64-v8a", apiLevel=34),
        deviceTier=tier,
        regionCode="ir",
        runtimeAbi="arm64-v8a",
        resourceVector=ResourceVector(
            cpuUnits=cpu_units,
            memoryBytes=total_ram,
            storageBytes=32 * _GIB,
            acceleratorUnits=0,
            modelSessionUnits=1,
        ),
        runtimeClasses=list(_runtimes_for(tier)),
        storage=StorageSpec(
            availableBytes=32 * _GIB,
            minimumFreeBytes=_GIB,
            maxAiStorageBytes=16 * _GIB,
        ),
        memory=MemorySpec(totalRamBytes=total_ram, availableBytes=total_ram, safetyReserveBytes=0),
        thermal=ThermalSpec(state="nominal"),
        battery=BatterySpec(levelBps=8_000, charging=True),
        network=NetworkSpec(type="wifi"),
    )
    return compute_effective_resource_budgets(
        capability=capability,
        contribution_multiplier_bps=_CONTRIBUTION_BPS,
    )


def build_devices() -> list[DeviceState]:
    devices: list[DeviceState] = []
    for tier, count, cpu_units, total_ram in _DEVICE_PLAN:
        budgets = _budgets_for(tier, cpu_units, total_ram)
        for index in range(count):
            devices.append(
                DeviceState(
                    worker_id=f"wrk-{tier.lower()}-{index:02d}",
                    tier=tier,
                    total_ram=total_ram,
                    budgets=budgets,
                    runtimes=_runtimes_for(tier),
                )
            )
    return devices


def build_tasks() -> list[ScenarioTask]:
    tasks: list[ScenarioTask] = []
    cursor = 0
    for runtime, count, cpu_units, memory_bytes, priority in _TASK_PLAN:
        for index in range(count):
            tasks.append(
                ScenarioTask(
                    task_id=f"tsk-{runtime}-{index:03d}",
                    runtime=runtime,
                    cpu_units=cpu_units,
                    memory_bytes=memory_bytes,
                    priority_bps=priority,
                    submitted_at=_BASE_TIME + timedelta(seconds=cursor),
                )
            )
            cursor += 1
    return tasks


def _within_scenario_caps(device: DeviceState, task: ScenarioTask) -> bool:
    if len(device.leases) >= tier_capacity(device.tier):
        return False
    if task.heavy and device.heavy_leases >= 1:
        return False
    ram_ceiling = device.total_ram * _RAM_CEILING_PERCENT // 100
    return device.reserved_memory + task.memory_bytes <= ram_ceiling


def _candidate(device: DeviceState, task: ScenarioTask) -> dict[str, object]:
    return {
        "workerId": device.worker_id,
        "input": {
            "featuresBps": {
                "modelLocality": 10_000,
                "trust": 10_000,
                "predictedLatency": 10_000,
                "batteryCharging": 10_000,
                "network": 10_000,
                "regionalCompliance": 10_000,
                "priceEfficiency": 10_000,
                "reliability": 10_000,
                "scarcityCost": 10_000,
            },
            "heartbeatAgeSeconds": 1,
            "batteryPercent": 80,
            "thermalState": "nominal",
            "attested": True,
            "consentCurrent": True,
            "modelDigestMatch": True,
            "modelAvailable": True,
            "runtimeAbiMatch": True,
            "regionAllowed": True,
            "networkPolicyAllowed": True,
            "available": True,
            "deviceTier": device.tier,
            "taskRuntimeClass": task.runtime,
            "workerRuntimeClasses": list(device.runtimes),
            "activeRuntimeClasses": list(device.leases),
            "taskCostUnits": task.cpu_units,
            "effectiveBudgets": {
                "cpuUnits": device.budgets.cpu_units,
                "memoryBytes": device.budgets.memory_bytes,
                "storageBytes": device.budgets.storage_bytes,
            },
            "reservedTotals": {
                "cpuUnits": device.reserved_cpu,
                "memoryBytes": device.reserved_memory,
                "storageBytes": device.reserved_storage,
            },
            "requestedTotals": {
                "cpuUnits": task.cpu_units,
                "memoryBytes": task.memory_bytes,
                "storageBytes": _STORAGE_REQUEST,
            },
        },
    }


def choose_worker(
    task: ScenarioTask,
    devices: list[DeviceState],
    router: RouterService,
) -> Placement:
    by_id = {device.worker_id: device for device in devices}
    candidates = [
        _candidate(device, task) for device in devices if _within_scenario_caps(device, task)
    ]
    if not candidates:
        return Placement(task.task_id, task.runtime, task.heavy, None, None, None, None, None)
    ranked = router.rank_workers(task_id=task.task_id, router_epoch=1, candidates=candidates)
    eligible = [row for row in ranked if row["eligible"]]
    if not eligible:
        return Placement(task.task_id, task.runtime, task.heavy, None, None, None, None, None)
    best_score = max(int(row["score"]) for row in eligible)
    tied = [row for row in eligible if int(row["score"]) == best_score]
    if task.heavy:
        chosen = max(tied, key=lambda row: (_TIER_RANK[by_id[row["workerId"]].tier], row["workerId"]))
    else:
        chosen = tied[0]
    winner = by_id[chosen["workerId"]]
    strongest = max(tied, key=lambda row: _TIER_RANK[by_id[row["workerId"]].tier])
    return Placement(
        task.task_id,
        task.runtime,
        task.heavy,
        winner.worker_id,
        winner.tier,
        int(chosen["score"]),
        best_score,
        by_id[strongest["workerId"]].tier,
    )


def _reserve(device: DeviceState, task: ScenarioTask) -> None:
    device.reserved_cpu += task.cpu_units
    device.reserved_memory += task.memory_bytes
    device.reserved_storage += _STORAGE_REQUEST
    device.leases.append(task.runtime)


def run_scenario() -> ScenarioReport:
    devices = build_devices()
    tasks = build_tasks()
    attempts = [
        QueueAttempt(
            attempt_id=f"att-{task.task_id}",
            workspace_id="ws-load",
            priority_bps=task.priority_bps,
            submitted_at=task.submitted_at,
            deadline_at=None,
            task_id=task.task_id,
        )
        for task in tasks
    ]
    order = {task.task_id: task for task in tasks}
    router = RouterService()
    placements: list[Placement] = []
    for attempt in rank_queue_attempts(attempts):
        task = order[attempt.task_id]
        placement = choose_worker(task, devices, router)
        if placement.worker_id is not None:
            _reserve(next(device for device in devices if device.worker_id == placement.worker_id), task)
        placements.append(placement)
    return ScenarioReport(devices=devices, tasks=tasks, placements=placements)


def assert_invariants(report: ScenarioReport) -> None:
    """Fail when a hardware cap is crossed, a task disappears, or a heavy task skips a stronger tie."""
    assert len(report.devices) == 100
    assert len(report.tasks) == 500
    assert len(report.assignments) + len(report.queued) == 500
    assert len({item.task_id for item in report.placements}) == 500
    assert report.queued, "every task was assigned; the queue never had to wait"

    for device in report.devices:
        assert len(device.leases) <= tier_capacity(device.tier)
        assert device.heavy_leases <= 1
        assert device.reserved_cpu <= device.budgets.cpu_units
        assert device.reserved_memory <= device.budgets.memory_bytes
        assert device.reserved_storage <= device.budgets.storage_bytes
        assert device.reserved_memory <= device.total_ram * _RAM_CEILING_PERCENT // 100

    for placement in report.assignments:
        assert placement.score == placement.best_score
        if placement.heavy:
            assert placement.tier == placement.strongest_tied_tier

    router = RouterService()
    for placement in report.queued:
        task = next(item for item in report.tasks if item.task_id == placement.task_id)
        assert choose_worker(task, report.devices, router).worker_id is None


def format_report(report: ScenarioReport) -> str:
    lines = [
        "سناریو: 100 دستگاه آماده، 500 تسک",
        f"تخصیص‌شده: {len(report.assignments)}",
        f"مانده در صف: {len(report.queued)}",
        "",
        "سطح | دستگاه | اجاره | سنگین",
    ]
    for tier in ("T1", "T2", "T3", "T4"):
        group = [device for device in report.devices if device.tier == tier]
        leases = sum(len(device.leases) for device in group)
        heavy = sum(device.heavy_leases for device in group)
        lines.append(f"{tier} | {len(group)} | {leases} | {heavy}")
    lines.extend(["", "تسک | کل | تخصیص | صف"])
    for runtime, count, *_rest in _TASK_PLAN:
        assigned = sum(1 for item in report.assignments if item.runtime == runtime)
        lines.append(f"{runtime} | {count} | {assigned} | {count - assigned}")
    busiest = max(
        (device.reserved_memory * 100 // device.total_ram for device in report.devices),
        default=0,
    )
    lines.extend(
        [
            "",
            f"بیشترین RAM اشغال‌شده: {busiest}% (سقف سناریو {_RAM_CEILING_PERCENT} درصد)",
            "بودجهٔ CPU و RAM و سقف همزمانی سطح دستگاه رد نشده است.",
            "تسک سنگین، بین گزینه‌های هم‌امتیاز، به سطح قوی‌تر رفته است.",
        ]
    )
    return "\n".join(lines)


def main() -> int:
    report = run_scenario()
    sys.stdout.buffer.write((format_report(report) + "\n").encode("utf-8"))
    try:
        assert_invariants(report)
    except AssertionError as exc:
        print(f"INVARIANT FAILED: {exc}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
