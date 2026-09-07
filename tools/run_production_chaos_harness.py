#!/usr/bin/env python3
"""Phase 7 production proof chaos harness — runs scenarios and writes plan evidence."""
from __future__ import annotations

import json
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "src" / "backend"
EVIDENCE_DIR = ROOT / "plan" / "evidence"
CHAOS_TEST = BACKEND / "tests" / "chaos" / "test_production_proof_scenarios.py"

SCENARIO_MAP = {
    "test_p7_chaos_20_workers_load_invariant": "P7-CHAOS-20-workers",
    "test_p7_chaos_56_task_catalog_execution_matrix": "P7-CHAOS-56-task-catalog",
    "test_p7_chaos_multi_assignment_exclusive_groups": "P7-CHAOS-multi-assignment",
    "test_p7_chaos_resource_exhaustion_no_overcommit": "P7-CHAOS-resource-exhaustion",
    "test_p7_chaos_worker_disconnect_retry_class": "P7-CHAOS-worker-disconnect",
    "test_p7_chaos_lease_expiry_rejects_writes": "P7-CHAOS-lease-expiry",
    "test_p7_chaos_stale_result_rejected": "P7-CHAOS-stale-result",
    "test_p7_chaos_runtime_crash_closed_code": "P7-CHAOS-runtime-crash",
    "test_p7_chaos_oom_server_retry_not_local": "P7-CHAOS-oom",
    "test_p7_chaos_thermal_failure_closed_code": "P7-CHAOS-thermal-failure",
    "test_p7_chaos_retry_exhaustion_terminal": "P7-CHAOS-retry-exhaustion",
    "test_p7_chaos_cloud_fallback_audit": "P7-CHAOS-cloud-fallback",
    "test_p7_chaos_reward_exactly_once": "P7-CHAOS-reward-exactly-once",
    "test_p7_chaos_long_context_summarize_plan": "P7-CHAOS-long-context-summarize",
    "test_p7_chaos_chunk_resume_fence_aware": "P7-CHAOS-chunk-resume",
    "test_p7_chaos_recursive_reduce_depth": "P7-CHAOS-recursive-reduce",
    "test_p7_chaos_model_corruption_rejected": "P7-CHAOS-model-corruption",
    "test_p7_chaos_model_update_during_residency": "P7-CHAOS-model-update",
    "test_p7_chaos_storage_pressure_eviction": "P7-CHAOS-storage-pressure",
    "test_p7_chaos_consent_30_to_50": "P7-CHAOS-consent-30-to-50",
    "test_p7_chaos_consent_50_to_30": "P7-CHAOS-consent-50-to-30",
    "test_p7_chaos_consent_revoke": "P7-CHAOS-consent-revoke",
    "test_p7_chaos_thermal_transition_concurrency": "P7-CHAOS-thermal-transition",
    "test_p7_chaos_websocket_replay": "P7-CHAOS-websocket-replay",
    "test_p7_chaos_stale_fence_writes": "P7-CHAOS-stale-fence-writes",
    "test_p7_chaos_duplicate_delivery_idempotent": "P7-CHAOS-duplicate-delivery",
}


def _run_pytest() -> tuple[int, dict[str, str]]:
    proc = subprocess.run(
        [
            sys.executable,
            "-m",
            "pytest",
            str(CHAOS_TEST),
            "-v",
            "--tb=no",
        ],
        cwd=str(BACKEND),
        capture_output=True,
        text=True,
        check=False,
    )
    outcomes: dict[str, str] = {}
    for line in proc.stdout.splitlines():
        if " PASSED" in line:
            name = line.split("::")[-1].split(" ")[0]
            outcomes[name] = "passed"
        elif " FAILED" in line:
            name = line.split("::")[-1].split(" ")[0]
            outcomes[name] = "failed"
    return proc.returncode, outcomes


def _write_evidence(task_id: str, *, status: str, test_name: str, notes: str = "") -> None:
    slug = task_id.lower().replace("p7-", "phase-07-p7-")
    path = EVIDENCE_DIR / f"{slug}.json"
    payload = {
        "status": status,
        "taskId": task_id,
        "test": test_name,
        "harness": "tools/run_production_chaos_harness.py",
        "generatedAt": datetime.now(UTC).isoformat(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "notes": notes or "Dev/staging invariant proof via pytest + source verify; live chaos deferred to staging deploy.",
    }
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    EVIDENCE_DIR.mkdir(parents=True, exist_ok=True)

    rollback_proc = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "run_rollback_drill_dry_run.py")],
        capture_output=True,
        text=True,
        check=False,
    )
    rollback_payload = json.loads(rollback_proc.stdout) if rollback_proc.stdout.strip() else {}
    t01_path = EVIDENCE_DIR / "phase-07-p7-t01-rollout-rollback-drill.json"
    t01_path.write_text(json.dumps(rollback_payload, indent=2) + "\n", encoding="utf-8")

    exit_code, outcomes = _run_pytest()
    scenario_results: list[dict[str, object]] = []
    for test_name, task_id in SCENARIO_MAP.items():
        status = outcomes.get(test_name, "missing")
        _write_evidence(task_id, status=status, test_name=test_name)
        scenario_results.append({"taskId": task_id, "test": test_name, "status": status})

    passed = sum(1 for item in scenario_results if item["status"] == "passed")
    rollup = {
        "status": "passed" if exit_code == 0 and rollback_proc.returncode == 0 else "failed",
        "phase": 7,
        "harness": "tools/run_production_chaos_harness.py",
        "generatedAt": datetime.now(UTC).isoformat(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "rollbackDrill": rollback_payload.get("status", "unknown"),
        "scenariosPassed": passed,
        "scenariosTotal": len(SCENARIO_MAP),
        "scenarios": scenario_results,
    }
    rollup_path = EVIDENCE_DIR / "phase-07-p7-t02-architecture-v1-closure-signoff.json"
    if rollup["status"] == "passed":
        rollup["signOff"] = {
            "architectureVersion": "v1",
            "decision": "implementation_closure_dev_complete",
            "productionDeployProof": "deferred_to_staging",
            "date": datetime.now(UTC).date().isoformat(),
        }
    rollup_path.write_text(json.dumps(rollup, indent=2) + "\n", encoding="utf-8")

    release_chaos = ROOT / "evidence" / "actual" / "release" / "tests" / "chaos.json"
    release_chaos.parent.mkdir(parents=True, exist_ok=True)
    release_chaos.write_text(
        json.dumps(
            {
                "schemaVersion": "1.0",
                "subject": "chaos",
                "status": rollup["status"],
                "verified": rollup["status"] == "passed",
                "generatedAt": datetime.now(UTC).isoformat(),
                "producer": "tools/run_production_chaos_harness.py",
                "scenariosPassed": passed,
                "scenariosTotal": len(SCENARIO_MAP),
                "classification": "IMPLEMENTED_DEV_ONLY",
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    print(json.dumps(rollup, indent=2))
    return 0 if rollup["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
