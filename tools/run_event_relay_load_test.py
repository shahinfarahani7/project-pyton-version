#!/usr/bin/env python3
"""Event relay contract and load-test harness."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def contract_checks() -> list[str]:
    errors: list[str] = []
    settings = (ROOT / "src/backend/edgemint/building_blocks/settings.py").read_text(encoding="utf-8")
    client = (ROOT / "src/backend/edgemint/building_blocks/eventing/durable_websocket_client.py").read_text(
        encoding="utf-8"
    )
    outbox = (ROOT / "src/backend/edgemint/building_blocks/eventing/transactional_outbox.py").read_text(
        encoding="utf-8"
    )
    inbox = (ROOT / "src/backend/edgemint/building_blocks/eventing/transactional_inbox.py").read_text(
        encoding="utf-8"
    )
    relay = (ROOT / "src/backend/edgemint/services/event_relay.py").read_text(encoding="utf-8")
    eventing = (ROOT / "src/backend/edgemint/building_blocks/eventing/relay.py").read_text(encoding="utf-8")
    inbox = (ROOT / "src/backend/edgemint/building_blocks/eventing/transactional_inbox.py").read_text(
        encoding="utf-8"
    )
    relay_bundle = relay + eventing + inbox
    gateway = (ROOT / "src/backend/edgemint/services/api_gateway.py").read_text(encoding="utf-8")

    if "websocket_max_in_flight: int = 256" not in settings:
        errors.append("settings missing max in-flight limit of 256")
    if "websocket_heartbeat_seconds: int = 20" not in settings:
        errors.append("settings missing 20 second heartbeat")
    if "websocket_ack_timeout_seconds: int = 30" not in settings:
        errors.append("settings missing 30 second ack timeout")
    if "InFlightLimiter" not in client or "max_in_flight: int = 256" not in client:
        errors.append("durable websocket client missing in-flight limiter")
    if "enqueue_outbox_event" not in outbox:
        errors.append("transactional outbox helper missing")
    if "record_inbox_before_ack" not in inbox:
        errors.append("transactional inbox helper missing")
    for token in [
        "resume_connection",
        "DelegatedTokenService",
        "claim_websocket_deliveries",
        "acknowledge_delivery",
        "BROWSER_CLIENT_MUST_USE_BFF",
    ]:
        if token not in relay_bundle:
            errors.append(f"event relay missing control:{token}")
    if '@app.websocket("/events/v1")' not in gateway:
        errors.append("api gateway missing public websocket edge")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="EdgeMint event relay load/contract harness")
    parser.add_argument("--contract-only", action="store_true")
    args = parser.parse_args()

    errors = contract_checks()
    report = {
        "status": "passed" if not errors else "failed",
        "mode": "contract-only" if args.contract_only else "live-load-not-implemented",
        "errors": errors,
    }
    print(json.dumps(report, indent=2))
    if errors:
        return 1
    if args.contract_only:
        return 0
    print("LIVE_LOAD_REQUIRES_POSTGRESQL_AND_RUNNING_RELAY", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
