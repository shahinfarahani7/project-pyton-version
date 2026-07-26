#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="full"; [[ "${1:-}" == "--spec-only" ]] && mode="spec-only" || [[ $# -eq 0 ]] || { echo "Usage: $0 [--spec-only]" >&2; exit 64; }
require_tool(){ command -v "$1" >/dev/null 2>&1 || { echo "BOOTSTRAP_BLOCKED:MISSING_TOOL:$1" >&2; exit 2; }; }
python tools/verify_package.py
bash tools/validate_all.sh
[[ "$mode" == "spec-only" ]] && { echo '{"status":"passed","mode":"spec-only"}'; exit 0; }
for tool in docker python node npm flutter terraform helm; do require_tool "$tool"; done
python - <<'PYV'
import sys
required = (3, 13, 14)
actual = sys.version_info[:3]
assert actual == required, f"Python {'.'.join(map(str, required))} required, found {sys.version}"
PYV
docker compose config >/dev/null
npm ci --ignore-scripts
npm run verify:web
python -m pip install --disable-pip-version-check -r src/backend/requirements-backend.lock
python -m pip check
python -m compileall -q src/backend/edgemint src/backend/tests
PYTHONPATH=src/backend python -m pytest -q src/backend/tests
python -m ruff check src/backend
python -m mypy src/backend/edgemint
(cd src/apps/worker && flutter pub get --enforce-lockfile && flutter analyze && flutter test)
terraform -chdir=deploy/terraform/aws fmt -check -recursive
terraform -chdir=deploy/terraform/aws init -backend=false -lockfile=readonly
terraform -chdir=deploy/terraform/aws validate
helm lint deploy/helm/edgemint -f deploy/helm/edgemint/values-ci.yaml
echo '{"status":"passed","mode":"full"}'
