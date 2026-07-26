#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python tools/generate_contracts.py >/dev/null
if ! git diff --quiet -- generated; then
  echo "GENERATED_DRIFT_DETECTED" >&2
  git diff --stat -- generated >&2 || true
  exit 1
fi
echo '{"status":"passed","drift":false}'
