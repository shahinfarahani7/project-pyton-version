#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
migration = (ROOT / "database/sql/013_websocket_outbox_expansion_replay.sql").read_text()
relay = (ROOT / "src/backend/edgemint/building_blocks/eventing/relay.py").read_text()
service = (ROOT / "src/backend/edgemint/services/event_relay.py").read_text()

checks = {
    "durable_outbox_expansion": "eventing.expand_outbox_batch" in migration,
    "idempotent_fanout": "ON CONFLICT (subscription_id, outbox_event_id) DO NOTHING" in migration,
    "worker_target_filter": "worker.principal_id = subscription.principal_id" in migration,
    "no_lease_token_in_delivery": "leaseToken" not in migration,
    "expired_sent_requeued": "ACK_TIMEOUT" in migration and "status = 'retry'" in migration,
    "resume_keeps_sequence": "next_sequence = next_sequence + 1" in migration,
    "relay_expands_before_claim": "await expand_outbox_events" in service,
    "transactional_expander": "async with transaction" in relay,
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'} {name}")
raise SystemExit(1 if failed else 0)
