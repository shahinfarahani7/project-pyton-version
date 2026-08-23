#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
service = (ROOT / "src/backend/edgemint/services/worker_registry.py").read_text()
commands = (ROOT / "src/backend/edgemint/workers/assignments.py").read_text()
mobile = (ROOT / "src/apps/worker/lib/runtime/assignment_coordinator.dart").read_text()
openapi = (ROOT / "contracts/openapi/edgemint-worker-api.yaml").read_text()
checks = {
    "production_202_endpoint": 'status_code=202' in service and 'complete_automatic_assignment' in service,
    "mobile_sends_inline_output": "'outputInline': utf8.decode(output.resultBytes)" in mobile,
    "lease_scoped_result_mac": "ResultSigner(signingMaterial: assignment.leaseToken)" in mobile,
    "digest_verified": 'resultSha256 mismatch' in commands,
    "mac_verified": 'result signature invalid' in commands,
    "fence_and_token_verified": 'self._verify_active_credential' in commands,
    "result_persisted": 'INSERT INTO public.results' in commands,
    "lease_secret_destroyed": 'DELETE FROM public.assignment_lease_credentials' in commands,
    "openapi_aligned": '- outputInline' in openapi and "$ref: '#/components/schemas/Completion'" in openapi,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items(): print(f"{'PASS' if ok else 'FAIL'} {name}")
raise SystemExit(1 if failed else 0)
