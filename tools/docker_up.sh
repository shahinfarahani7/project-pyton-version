#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ENV_FILE="${ENV_FILE:-.env.docker}"
if [[ ! -f "$ENV_FILE" ]]; then
  if [[ -f ".env.docker.example" ]]; then
    cp ".env.docker.example" "$ENV_FILE"
    echo "Created $ENV_FILE from .env.docker.example"
  else
    echo "Missing $ENV_FILE and .env.docker.example" >&2
    exit 1
  fi
fi

python tools/generate_compose_backend.py

COMPOSE=(docker compose --env-file "$ENV_FILE" -f compose.yaml -f compose.backend.yaml)
if [[ "${WITH_PORTALS:-0}" == "1" ]]; then
  COMPOSE+=(-f compose.portals.yaml)
fi

"${COMPOSE[@]}" "$@"
