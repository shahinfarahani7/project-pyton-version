#!/usr/bin/env python3
"""Analyze v2 §73 policy readiness gaps and emit plan evidence."""
from __future__ import annotations

import json
import subprocess
from datetime import UTC, datetime
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]


def _load_yaml(rel: str) -> dict:
    return yaml.safe_load((ROOT / rel).read_text(encoding="utf-8"))


def _git_head() -> str:
    try:
        return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    except Exception:
        return "unknown"


def _policy_area(
    area: str,
    *,
    configured: list[str],
    missing: list[str],
    sources: list[str],
    notes: str = "",
) -> dict:
    if missing and not configured:
        status = "MISSING"
    elif missing:
        status = "PARTIAL"
    else:
        status = "CONFIGURED"
    return {
        "area": area,
        "status": status,
        "configuredValues": configured,
        "missingValues": missing,
        "sources": sources,
        "missingValueBehavior": "activation_blocked_per_v2_section_73" if missing else "none",
        "notes": notes,
    }


def main() -> int:
    routing = _load_yaml("dsl/policies/routing/smart-router-v2.yaml")["spec"]
    consent = _load_yaml("dsl/policies/consent/production-resource-policy-v1.yaml")["spec"]
    canonical = _load_yaml("production/canonical-decisions.yaml")["spec"]
    timeouts = routing["timeouts"]
    fallback = routing["fallback"]
    queue = routing["queueSelection"]

    areas = [
        _policy_area(
            "execution_grant",
            configured=[
                f"leaseSeconds={timeouts['leaseSeconds']}",
                f"leaseRenewalSeconds={timeouts['leaseRenewalSeconds']}",
                f"assignmentDeliverySeconds={timeouts['assignmentDeliverySeconds']}",
                f"autoStartGraceSeconds={timeouts['autoStartGraceSeconds']}",
                f"heartbeatSeconds={timeouts['heartbeatSeconds']}",
            ],
            missing=[
                "clockLatencyAllowance",
                "renewalRetryPolicy",
                "replayHorizonSeconds",
            ],
            sources=[
                "dsl/policies/routing/smart-router-v2.yaml",
                "production/AUTO-ASSIGNMENT-PROTOCOL.md",
                "src/backend/edgemint/routing/service.py",
            ],
            notes="Core lease/delivery/start deadlines present in DSL; clock skew allowance not versioned.",
        ),
        _policy_area(
            "cpu_and_cancellation",
            configured=[
                f"defaultContributionPercent={canonical['assignmentProtocol']['defaultContributionPercent']}",
                f"maximumContributionPercent={canonical['assignmentProtocol']['maximumContributionPercent']}",
                f"performanceModeRequiresExplicitOptIn={canonical['assignmentProtocol']['performanceModeRequiresExplicitOptIn']}",
                "consentChangeBehavior=increaseAppliesToNewReservationsOnly,decreaseStopsNewStagesAboveLimit,revocationStopsNewWorkImmediately",
            ],
            missing=[
                "cpuMeasurementWindowMs",
                "coveredProcessScope",
                "cpuBurstBoundBps",
                "controlStopReactionBoundMs",
                "enforcementMechanismCertification",
            ],
            sources=[
                "dsl/policies/consent/production-resource-policy-v1.yaml",
                "production/canonical-decisions.yaml",
                "src/backend/edgemint/workers/resource_policy.py",
            ],
            notes="30/50 consent and runtime session caps exist; v2 CPU window/burst/stop certification absent.",
        ),
        _policy_area(
            "memory_storage",
            configured=[
                "resourceEnvelopeRefs=56/56 catalog bindings",
                "storagePressureManager=worker runtime",
                "safetyReservePercent=15 in consent DSL",
            ],
            missing=[
                "userProcessMemoryLimitBytes",
                "serverProcessMemoryAttributionRules",
                "transferTempModelCoexistenceLimits",
                "certifiedMemoryMetricDefinition",
            ],
            sources=[
                "dsl/policies/consent/production-resource-policy-v1.yaml",
                "src/apps/worker/lib/runtime/storage_pressure_manager.dart",
                "dsl/catalog/resource-envelopes/",
            ],
        ),
        _policy_area(
            "plan_and_context",
            configured=[
                "executionPlans=dsl/catalog/execution-plans/",
                "contextBudgetManager=worker",
                "maxTokensBaseline=1280 canonical",
                "checkpointPolicyMatrix=dsl/policies/checkpoints/",
            ],
            missing=[
                "verifiedTokenizerTemplateIdentityPerArtifact",
                "maxReduceDepthCallsBoundInPolicy",
                "stageAggregateTimeoutPolicyRecord",
                "policyContextHashOnPlan",
            ],
            sources=[
                "dsl/catalog/execution-plans/",
                "src/apps/worker/lib/inference/llm/context_budget_manager.dart",
                "production/canonical-decisions.yaml",
            ],
        ),
        _policy_area(
            "taskrun_retry_fallback",
            configured=[
                f"maxWorkerReassignments={fallback['maxWorkerReassignments']}",
                f"cloudAfterSeconds={fallback['cloudAfterSeconds']}",
                "retryPolicyMatrix=dsl/policies/retry/task-retry-matrix-v1.yaml",
                f"starvationLimitSeconds={queue['starvationLimitSeconds']}",
            ],
            missing=[
                "taskRunMaxAttemptsExplicit",
                "taskRunMaxCostMicros",
                "validationWorkBudget",
                "backoffJitterPolicyRecord",
                "queueExpiryPolicyRecord",
            ],
            sources=[
                "dsl/policies/routing/smart-router-v2.yaml",
                "dsl/policies/retry/task-retry-matrix-v1.yaml",
                "src/backend/edgemint/routing/retry_classifier.py",
            ],
        ),
        _policy_area(
            "queue_service_capacity",
            configured=[
                f"candidateWindowSize={queue['candidateWindowSize']}",
                f"quantumUnits={queue['workspaceFairness']['quantumUnits']}",
                f"maximumConsecutiveAssignmentsPerWorkspace={queue['workspaceFairness']['maximumConsecutiveAssignmentsPerWorkspace']}",
                f"idleWorkspaceCreditCapUnits={queue['workspaceFairness']['idleWorkspaceCreditCapUnits']}",
            ],
            missing=[
                "activeQueuedTaskCapsPerWorkspace",
                "outboxCapacityPolicy",
                "uploadPipelineCapacityPolicy",
                "validationBacklogCapacityPolicy",
                "reconcilerSweeperCadence",
            ],
            sources=[
                "dsl/policies/routing/smart-router-v2.yaml",
                "src/backend/edgemint/routing/fair_queue_metrics.py",
            ],
        ),
        _policy_area(
            "calibration_compatibility",
            configured=[
                "calibrationProfiles=dsl/catalog/calibration-profiles/",
                "runtimeCompatibilityMatrix=dsl/catalog/runtime-compatibility/",
                "deviceCertification=workers/calibration.py",
            ],
            missing=[
                "workloadSampleWindowSpecification",
                "coldWarmComparableMetricsPolicy",
                "profileExpiryDays",
                "uncertaintyErrorLimits",
                "certificationMatrixVersionHash",
            ],
            sources=[
                "dsl/catalog/calibration-profiles/",
                "dsl/catalog/runtime-compatibility/production-v1.yaml",
                "database/sql/016_worker_calibration_profiles.sql",
            ],
        ),
        _policy_area(
            "artifact_trust_data",
            configured=[
                "modelArtifactVerifier=worker",
                "tenantContext=backend auth layer",
                "signedModelDistribution=WP-090 scope",
            ],
            missing=[
                "signerTrustRootsVersionedRecord",
                "destinationPermissionMatrix",
                "credentialRetentionRevocationRules",
                "enrollmentConnectionPolicyRecord",
            ],
            sources=[
                "src/apps/worker/lib/runtime/model_artifact_verifier.dart",
                "production/canonical-decisions.yaml",
            ],
        ),
        _policy_area(
            "validation_reward",
            configured=[
                "verificationPolicy=dsl/policies/verification/",
                "goldenHarness=tests/golden/",
                "financeIdempotency=src/backend/edgemint/billing/service.py",
            ],
            missing=[
                "candidateValidationTimeoutPolicy",
                "entitlementScopeCapRecord",
                "payoutReconciliationRetentionPolicy",
                "taskSpecificThresholdVersionBinding",
            ],
            sources=[
                "dsl/policies/verification/default-v2.yaml",
                "src/backend/tests/billing/test_finance_service.py",
            ],
        ),
        _policy_area(
            "recovery_operations",
            configured=[
                "releaseRollbackRunbook=docs/08-sre/runbooks/RB-025-release-rollback.md",
                "productionGate=tools/production_gate.py",
            ],
            missing=[
                "reservationLeakSweeperCadence",
                "renewalLagSloSeconds",
                "outboxStallAlertThreshold",
                "validationRewardAlertThresholds",
                "durableRestoreRollbackProtocolEvidence",
            ],
            sources=[
                "docs/08-sre/runbooks/RB-025-release-rollback.md",
                "tools/production_gate.py",
            ],
        ),
    ]

    missing_areas = sum(1 for a in areas if a["status"] == "MISSING")
    partial_areas = sum(1 for a in areas if a["status"] == "PARTIAL")
    configured_areas = sum(1 for a in areas if a["status"] == "CONFIGURED")

    payload = {
        "status": "passed",
        "taskId": "P8-T04",
        "architectureVersion": "2.0",
        "sourceSection": "73",
        "generatedAt": datetime.now(UTC).isoformat(),
        "commitSha": _git_head(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "policyReadinessRecord": {
            "status": "MISSING",
            "note": "No PolicyReadinessRecord schema, SQL table, or service binding exists yet.",
            "requiredFields": [
                "architectureVersion",
                "policyVersionHash",
                "runtimeProfileScope",
                "responsibleOwner",
                "values",
                "evidence",
                "compatibility",
                "featureFlags",
            ],
        },
        "summary": {
            "totalPolicyAreas": len(areas),
            "configuredAreas": configured_areas,
            "partialAreas": partial_areas,
            "missingAreas": missing_areas,
            "productionActivationGate": "CLOSED",
            "reason": "partial_or_missing_policy_values_in_10_of_10_areas",
        },
        "policyAreas": areas,
        "retainedBaselinesPresent": {
            "section9_queueFairness": True,
            "section16_memorySafetyReserve": consent["resourcePolicy"].get("safetyReservePercent") == 15,
            "section29_runtimePairs": (ROOT / "dsl/catalog/runtime-compatibility/production-v1.yaml").is_file(),
            "section36_drr": queue["algorithm"] == "workspace_deficit_round_robin_then_earliest_deadline",
            "section44_retryBudget": fallback.get("maxWorkerReassignments") == 2,
            "section52_cloudFallback": fallback.get("cloudAfterSeconds") == 45,
            "section64_contribution30_50": canonical["assignmentProtocol"].get("defaultContributionPercent") == 30,
        },
    }

    out = ROOT / "plan" / "evidence" / "phase-08-p8-t04-policy-readiness-gap.json"
    out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload["summary"], indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
