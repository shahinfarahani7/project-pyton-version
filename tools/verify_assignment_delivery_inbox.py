#!/usr/bin/env python3
"""Verify durable assignment delivery inbox artifacts for P8-A03 / T03."""

from __future__ import annotations

import json
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _git_sha() -> str:
    try:
        return (
            subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True)
            .strip()
        )
    except Exception:
        return "unknown"


def _run_pytest(test_path: Path) -> bool:
    result = subprocess.run(
        [sys.executable, "-m", "pytest", str(test_path), "-q"],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    return result.returncode == 0


def main() -> int:
    errors: list[str] = []
    artifacts = {
        "sql": ROOT / "database/sql/027_worker_assignment_delivery_inbox.sql",
        "serverService": ROOT / "src/backend/edgemint/workers/assignment_delivery_inbox.py",
        "serverWiring": ROOT / "src/backend/edgemint/workers/assignments.py",
        "serverEndpoint": ROOT / "src/backend/edgemint/services/worker_registry.py",
        "transactionalInbox": ROOT / "src/backend/edgemint/building_blocks/eventing/transactional_inbox.py",
        "durableWsClient": ROOT / "src/backend/edgemint/building_blocks/eventing/durable_websocket_client.py",
        "workerInbox": ROOT / "src/apps/worker/lib/runtime/assignment_inbox.dart",
        "workerCoordinator": ROOT / "src/apps/worker/lib/runtime/assignment_coordinator.dart",
        "backendTests": ROOT / "src/backend/tests/workers/test_assignment_delivery_inbox.py",
        "eventRelayTests": ROOT / "src/backend/tests/event_relay/test_eventing_contracts.py",
        "workerTests": ROOT / "src/apps/worker/test/runtime/assignment_inbox_test.dart",
        "wsReplayVerifier": ROOT / "tools/verify_websocket_replay_source.py",
    }
    for label, path in artifacts.items():
        if not path.is_file():
            errors.append(f"missing artifact ({label}): {path.relative_to(ROOT)}")

    sql = artifacts["sql"].read_text(encoding="utf-8") if artifacts["sql"].is_file() else ""
    for token in (
        "worker_assignment_deliveries",
        "record_worker_assignment_delivery",
        "acknowledge_worker_assignment_delivery",
        "ON CONFLICT (assignment_id, worker_device_id, fence_token) DO NOTHING",
    ):
        if token not in sql:
            errors.append(f"SQL missing token: {token}")

    backend_passed = _run_pytest(artifacts["backendTests"])
    if not backend_passed:
        errors.append("backend pytest failed for test_assignment_delivery_inbox.py")

    eventing_passed = _run_pytest(artifacts["eventRelayTests"])
    if not eventing_passed:
        errors.append("backend pytest failed for test_eventing_contracts.py")

    ws_replay = subprocess.run(
        [sys.executable, str(artifacts["wsReplayVerifier"])],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    ws_replay_passed = ws_replay.returncode == 0
    if not ws_replay_passed:
        errors.append("verify_websocket_replay_source.py failed")

    worker_test_status = "SKIPPED"
    try:
        worker_test = subprocess.run(
            ["flutter", "test", str(artifacts["workerTests"])],
            cwd=ROOT / "src/apps/worker",
            capture_output=True,
            text=True,
        )
        if worker_test.returncode == 0:
            worker_test_status = "PASSED"
        elif worker_test.returncode == 69:
            worker_test_status = "SKIPPED_NETWORK"
            errors.append("flutter test skipped: pub.dev/network unavailable")
        else:
            worker_test_status = "FAILED"
            errors.append("flutter test failed for assignment_inbox_test.dart")
    except FileNotFoundError:
        worker_test_status = "SKIPPED_NO_FLUTTER"
        errors.append("flutter CLI unavailable; assignment_inbox_test.dart not executed")

    hard_errors = [
        error
        for error in errors
        if not error.startswith("flutter test skipped") and "flutter CLI unavailable" not in error
    ]

    evidence = {
        "status": "passed" if not hard_errors else "failed",
        "taskId": "P8-A03",
        "auditId": "A03",
        "acceptanceCase": "T03",
        "architectureVersion": "2.0",
        "sourceSections": ["7", "20", "21", "22", "39", "40"],
        "generatedAt": datetime.now(UTC).isoformat(),
        "commitSha": _git_sha(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "artifacts": {k: str(v.relative_to(ROOT)).replace("\\", "/") for k, v in artifacts.items()},
        "upstreamEvidence": [
            "plan/evidence/phase-07-p7-chaos-websocket-replay.json",
            "plan/evidence/phase-07-p7-chaos-duplicate-delivery.json",
            "tools/verify_websocket_replay_source.py",
        ],
        "t03Scenario": {
            "title": "Crash before send; ACK loss; duplicate delivery; reconnect bootstrap",
            "pollDeliveryInbox": backend_passed,
            "websocketReplayVerifier": ws_replay_passed,
            "eventingContracts": eventing_passed,
            "workerLocalInboxTest": worker_test_status,
            "integrationHarness": "NOT_RUN",
        },
        "gaps": [
            "T03 live crash/ACK-loss integration harness NOT_RUN",
            "OpenAPI contract sync for :inboxBootstrap pending",
            "WebSocket assignment push path not production-proven",
        ],
        "errors": errors,
    }

    out_path = ROOT / "plan/evidence/phase-08-p8-a03-assignment-delivery-inbox.json"
    out_path.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence, indent=2))
    return 0 if evidence["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
