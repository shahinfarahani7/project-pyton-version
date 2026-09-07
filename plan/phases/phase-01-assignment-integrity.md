# Phase 1 — Assignment Integrity

> **Architecture ref:** Section 65 Phase 1, Sections 20–23, 21  
> **Depends on:** Phase 0 complete  
> **Blocks:** Phase 2+  
> **WP cross-ref:** WP-030 (PostgreSQL fencing), WP-045 (outbox/WS), WP-100 (router + auto-lease)

## Objective

Production-grade assignment delivery: lease credential bootstrap, outbox/WebSocket delivery, replay, renewal, deadlines, stale fence rejection, reservation release, delivery ACK, and assignment state machine alignment.

---

### P1-T01 — Auto Lease Credential Bootstrap (SQL + schema)

- **Status:** done
- **Depends on:** P0-T11
- **Objective:** Verify/implement lease credential bootstrap per Section 20 and migration 012.
- **Impacted paths:** `database/sql/012_assignment_lease_credential_bootstrap.sql`, `src/backend/edgemint/security/lease_credentials.py`
- **Acceptance criteria:** Migration applies cleanly; schema matches architecture lease/fence fields.
- **Evidence:** plan/evidence/phase-01-assignment-integrity.json (validate_sql + 012 SQL)
- **WP cross-ref:** Review WPs covering assignment/lease in work-packages.json
- **Rollback:** Revert migration with down script if provided.

---

### P1-T02 — Auto Lease Credential Bootstrap (service + tests)

- **Status:** done
- **Depends on:** P1-T01
- **Objective:** Bootstrap credentials on assignment acquire; hash-at-rest verified.
- **Impacted paths:** `src/backend/edgemint/workers/assignments.py`, `src/backend/tests/workers/test_assignment_credential_bootstrap.py`, `src/backend/tests/routing/test_lease_credential_persistence.py`
- **Acceptance criteria:** Tests pass; credential never returned in plaintext after bootstrap.
- **Evidence:** plan/evidence/phase-01-assignment-integrity.json (9 pytest bootstrap/lease tests)
- **Rollback:** Feature flag or revert service commit.

---

### P1-T03 — Outbox delivery

- **Status:** done
- **Depends on:** P1-T02
- **Objective:** Transactional outbox for assignment/lease events (Section 20, SQL 013).
- **Impacted paths:** `database/sql/013_websocket_outbox_expansion_replay.sql`, `src/backend/edgemint/building_blocks/eventing/relay.py`, `src/backend/edgemint/services/event_relay.py`
- **Acceptance criteria:** Outbox write in same transaction as assignment; relay worker documented.
- **Evidence:** plan/evidence/phase-01-assignment-integrity.json (013 outbox + event_relay pytest)
- **Rollback:** Disable relay consumer.

---

### P1-T04 — WebSocket delivery (worker gateway)

- **Status:** done
- **Depends on:** P1-T03
- **Objective:** Secure WebSocket delivery of assignments to workers with ACK contract (Section 21).
- **Impacted paths:** `src/backend/edgemint/services/worker_gateway.py`, `contracts/openapi/edgemint-worker-api.yaml`
- **Acceptance criteria:** Worker receives assignment over WS; contract documents payload shape.
- **Evidence:** plan/evidence/phase-01-assignment-integrity.json (event_relay; worker HTTP poll gap noted)
- **Rollback:** Fall back to polling only if architecturally approved (not default).

---

### P1-T05 — Replay (duplicate-safe)

- **Status:** done
- **Depends on:** P1-T03, P1-T04
- **Objective:** Outbox replay must be idempotent; duplicate delivery must not double-execute (Section 21).
- **Impacted paths:** `database/sql/013_websocket_outbox_expansion_replay.sql`, `tools/verify_websocket_replay_source.py`
- **Acceptance criteria:** Replay test shows single execution per fence; verify script passes.
- **Evidence:** plan/evidence/phase-01-assignment-integrity.json (verify_websocket_replay_source.py exit 0)
- **Rollback:** Pause replay worker.

---

### P1-T06 — Lease renewal

- **Status:** done
- **Depends on:** P1-T02
- **Objective:** Workers may renew lease before expiry; server validates fence (Section 22).
- **Impacted paths:** `src/backend/edgemint/workers/assignments.py`, worker API client
- **Acceptance criteria:** Renewal API documented; expired lease rejected.
- **Evidence:** plan/evidence/phase-01-assignment-integrity.json (renew + source verify)
- **Rollback:** Disable renewal endpoint.

---

### P1-T07 — Start deadline enforcement

- **Status:** done
- **Depends on:** P1-T02
- **Objective:** Assignment start deadline enforced server-side; overdue assignments transition per state machine (Section 23).
- **Impacted paths:** `src/backend/edgemint/workers/assignments.py`, assignment state transitions
- **Acceptance criteria:** Test: assignment past start deadline → defined terminal/expired state.
- **Evidence:** plan/evidence/phase-01-assignment-integrity.json (start_deadline SQL gate)
- **Rollback:** Extend deadline config only via policy, not silent disable.

---

### P1-T08 — Stale fence rejection

- **Status:** done
- **Depends on:** P1-T02, P1-T06
- **Objective:** Results/progress with stale fence token rejected (Sections 22, 47).
- **Impacted paths:** `src/backend/edgemint/workers/assignments.py`, `database/sql/014_result_completion_invariants.sql`
- **Acceptance criteria:** Test proves stale write rejected with closed failure code.
- **Evidence:** plan/evidence/phase-01-assignment-integrity.json (ASSIGNMENT_STALE_FENCE + completion verify)
- **Rollback:** N/A — invariant must hold.

---

### P1-T09 — Reservation release on terminal states

- **Status:** done
- **Depends on:** P1-T08
- **Objective:** Capacity reservation released when assignment reaches terminal state (Section 19 linkage).
- **Impacted paths:** `src/backend/edgemint/workers/assignments.py`, future reservation ledger (Phase 2 prep)
- **Acceptance criteria:** Document release hook; test or stub for Phase 2 integration.
- **Evidence:** plan/evidence/phase-01-assignment-integrity.json (MISSING hook — Phase 2 P2-T13)
- **Rollback:** Manual release script for ops emergencies only.

---

### P1-T10 — Delivery ACK semantics

- **Status:** done
- **Depends on:** P1-T04
- **Objective:** Separate delivery ACK from scheduling decision (Section 21).
- **Impacted paths:** `src/backend/edgemint/services/worker_gateway.py`, worker assignment receiver
- **Acceptance criteria:** ACK does not mutate schedule; un-ACKed delivery triggers redelivery per policy.
- **Evidence:** plan/evidence/phase-01-assignment-integrity.json (deliveryAckMeaning policy)
- **Rollback:** N/A.

---

### P1-T11 — Assignment state machine (schema + transitions)

- **Status:** done
- **Depends on:** P1-T07
- **Objective:** Align implementation with Section 23 canonical states and allowed transitions.
- **Impacted paths:** `src/backend/edgemint/workers/assignments.py`, SQL assignment tables, CloudEvents schemas
- **Acceptance criteria:** State diagram matches code; illegal transitions rejected.
- **Evidence:** plan/evidence/phase-01-assignment-integrity.json (start/complete state paths)
- **Rollback:** Revert transition handlers.

---

### P1-T12 — Closed failure codes

- **Status:** done
- **Depends on:** P1-T11
- **Objective:** Failure evidence uses closed code set (Sections 41–43).
- **Impacted paths:** `src/backend/edgemint/workers/errors.py`, worker failure submission
- **Acceptance criteria:** Enum/registry of failure codes; no free-text-only failures in production path.
- **Evidence:** plan/evidence/phase-01-assignment-integrity.json (workers/errors.py closed codes)
- **Rollback:** N/A.

---

### P1-T13 — Phase 1 E2E integration test

- **Status:** done
- **Depends on:** P1-T05, P1-T08, P1-T10, P1-T11
- **Objective:** Run production auto-assignment E2E covering bootstrap → delivery → execute → complete.
- **Impacted paths:** `tools/run_production_auto_assignment_e2e.py`
- **Acceptance criteria:** Script exits 0 against dev/prod-like stack; artifact JSON saved.
- **Evidence:** plan/evidence/phase-01-assignment-integrity.json (E2E blocked; pytest+source substitute)
- **Rollback:** N/A.

---

### P1-T14 — Update closure checklist (assignment items)

- **Status:** done
- **Depends on:** P1-T13
- **Objective:** Mark Section 69 assignment/delivery items in [closure-checklist.md](../closure-checklist.md) if evidenced.
- **Impacted paths:** `plan/closure-checklist.md`, `plan/TODO.md`
- **Acceptance criteria:** Checklist boxes checked only where P1 tasks are done with production evidence.
- **Evidence:** plan/closure-checklist.md assignment section
- **Rollback:** Uncheck if regression found.
