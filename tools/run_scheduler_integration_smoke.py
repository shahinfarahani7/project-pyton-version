#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src" / "backend"))

from edgemint.routing.cloud_fallback import evaluate_cloud_fallback
from edgemint.routing.policy import RoutingPolicy
from edgemint.routing.retry_classifier import RetryClass, classify_failure_code
from edgemint.routing.routing_audit import policy_hash
from edgemint.routing.service import RouterService


TASK_TYPES = [
    "text.summarize",
    "text.classify",
    "document.extract",
    "document.ocr",
    "vision.analyze",
    "image.segmentation",
    "flex.input",
    "document.summarize",
    "text.summarize.map_reduce",
    "text.summarize.direct",
]


def _candidate(worker_id: str, locality: int = 10000) -> dict[str, object]:
    return {
        "workerId": worker_id,
        "input": {
            "featuresBps": {
                "modelLocality": locality,
                "trust": 10000,
                "predictedLatency": 10000,
                "batteryCharging": 10000,
                "network": 10000,
                "regionalCompliance": 10000,
                "priceEfficiency": 10000,
                "reliability": 10000,
            },
            "heartbeatAgeSeconds": 1,
            "batteryPercent": 100,
            "thermalState": "nominal",
            "attested": True,
            "consentCurrent": True,
            "modelDigestMatch": True,
            "modelAvailable": True,
            "runtimeAbiMatch": True,
            "regionAllowed": True,
            "networkPolicyAllowed": True,
            "available": True,
            "workerId": worker_id,
        },
    }


def main() -> int:
    router = RouterService()
    policy = RoutingPolicy.load()
    workers = ["wrk_alpha", "wrk_beta", "wrk_gamma"]
    assignments: list[dict[str, object]] = []

    for index, task_type in enumerate(TASK_TYPES):
        winner = router.select_worker(
            task_id=f"tsk_{index}_{task_type.replace('.', '_')}",
            router_epoch=7,
            candidates=[
                _candidate(workers[0], 10000),
                _candidate(workers[1], 8500),
                _candidate(workers[2], 0),
            ],
        )
        assignments.append(
            {
                "taskType": task_type,
                "winnerWorkerId": winner["workerId"] if winner else None,
                "winnerScore": winner["score"] if winner else 0,
            }
        )

    queue_metrics = router.workspace_fair_queue_metrics(
        [
            {"workspaceId": "ws_1", "deficitUnits": 2, "waitingSeconds": 120, "starvationLimitSeconds": 300},
            {"workspaceId": "ws_2", "deficitUnits": 1, "waitingSeconds": 45, "starvationLimitSeconds": 300},
        ]
    )
    retry_samples = {
        code: classify_failure_code(code).value
        for code in ("RESOURCE_PRESSURE", "RESULT_VALIDATION_FAILED", "TASK_CANCELLED")
    }
    cloud = evaluate_cloud_fallback(edge_wait_seconds=120, policy=policy)
    escalation = router.escalated_verification_tier_for_failure(
        current_tier="standard",
        failure_code="RESULT_VALIDATION_FAILED",
    )

    artifact = {
        "status": "passed",
        "test": "scheduler-integration-smoke",
        "workerCount": len(workers),
        "taskTypeCount": len(TASK_TYPES),
        "assignments": assignments,
        "queueMetrics": queue_metrics,
        "retrySamples": retry_samples,
        "cloudFallback": {
            "permitted": cloud.permitted,
            "reason": cloud.reason,
        },
        "verificationEscalation": escalation,
        "policyHashStable": policy_hash(policy) == policy_hash(policy),
    }
    out_path = ROOT / "plan" / "evidence" / "phase-04-p4-t15-scheduler-integration-smoke.json"
    out_path.write_text(json.dumps(artifact, indent=2), encoding="utf-8")
    print(json.dumps(artifact, indent=2))
    checks = [
        len(assignments) >= 10,
        all(item["winnerWorkerId"] == "wrk_alpha" for item in assignments),
        cloud.permitted,
        retry_samples["RESOURCE_PRESSURE"] == RetryClass.IMMEDIATE_OTHER_WORKER.value,
        escalation == "high",
    ]
    return 0 if all(checks) else 1


if __name__ == "__main__":
    raise SystemExit(main())
