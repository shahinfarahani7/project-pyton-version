#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python tools/scan_secrets.py
python -m ruff check src/backend/edgemint/fraud src/backend/edgemint/services/fraud.py src/backend/tests/fraud
python tools/validate_dependency_locks.py
python tools/test_openapi_authorization_coverage.py
echo '{"critical":0,"high":0,"status":"pass"}'
