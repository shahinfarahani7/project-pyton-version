#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    assignments = (ROOT / "src/backend/edgemint/workers/assignments.py").read_text()
    registry = (ROOT / "src/backend/edgemint/services/worker_registry.py").read_text()
    router = (ROOT / "src/backend/edgemint/routing/service.py").read_text()
    sql = (ROOT / "database/sql/008_auto_assignment_protocol.sql").read_text()
    migration = (ROOT / "database/sql/012_assignment_lease_credential_bootstrap.sql").read_text()
    worker_client = (ROOT / "src/apps/worker/lib/api/worker_api_client.dart").read_text()
    checks = {
        "router_creates_encrypted_credential_atomically": (
            "acquire_assignment_lease" in router
            and "INSERT INTO public.assignment_lease_credentials" in router
        ),
        "bootstrap_is_target_device_only": (
            "assignment.worker_device_id = :worker_device_id" in assignments
            and "credential.worker_device_id = assignment.worker_device_id" in assignments
        ),
        "production_start_endpoint": '"/assignments/{assignment_id}:started"' in registry,
        "production_renew_endpoint": '"/assignments/{assignment_id}:renew"' in registry,
        "start_uses_postgresql_fence_gate": "start_auto_assigned_work" in assignments,
        "renew_uses_monotonic_postgresql_gate": "renew_auto_assignment_lease" in assignments,
        "start_and_renew_write_outbox": (
            'event_type="assignment.started"' in assignments
            and 'event_type="assignment.lease_renewed"' in assignments
        ),
        "mobile_client_can_renew": "Future<CommandReceipt> renewAssignment" in worker_client,
        "attestation_status_aligned": (
            "device.attestation_status = 'verified'" in sql
            and 'session.attestation_status != "verified"' in assignments
        ),
        "credential_table_has_no_plaintext_column": (
            "lease_token_ciphertext" in migration and "lease_token varchar" not in migration.lower()
        ),
        "no_accept_reject": all(
            token not in (assignments + registry).lower()
            for token in ("acceptassignment", "rejectassignment", "assignmentoffer")
        ),
    }
    failed = [name for name, passed in checks.items() if not passed]
    print(
        json.dumps(
            {
                "status": "passed" if not failed else "failed",
                "test": "production-auto-assignment-source-contract",
                "checks": checks,
                "failed": failed,
            },
            indent=2,
        )
    )
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
