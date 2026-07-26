# EdgeMint Cursor Execution Order

## Purpose

This runbook defines the authoritative order for implementing EdgeMint with Cursor. It must be used together with:

- `START-HERE.md`
- `cursor/CURSOR-MASTER-PROMPT.md`
- `cursor/STOP-RULES.md`
- `cursor/work-packages.json`
- `cursor/execution-units.json`
- `cursor/VERIFICATION-PROMPTS.md`

The JSON execution contracts remain authoritative when any generated prose differs from them.

## Non-negotiable selection rule

The repository uses a dependency DAG, not an unrestricted checklist.

> Select the lowest-numbered ready Work Package whose dependencies are complete. Never execute two Work Packages that overlap `allowedPaths` concurrently.

A Work Package is **ready** only when:

1. Every declared dependency is marked complete in `cursor/project-state.json`.
2. Every dependency evidence file exists and is bound to the current repository state.
3. The current Work Package has no unresolved external blocker required for its implementation.
4. No concurrently running Work Package overlaps its `allowedPaths`.

## Before the first implementation change

Run these steps from the repository root:

```bash
python tools/verify_package.py
bash tools/validate_all.sh
python tools/validate_cursor_plan.py
python tools/validate_traceability.py
```

Then read, in this order:

1. `START-HERE.md`
2. `production/canonical-decisions.yaml`
3. `production/AUTO-ASSIGNMENT-PROTOCOL.md`
4. `production/WEBSOCKET-EVENT-RELAY-ARCHITECTURE.md`
5. `database/README.md`
6. `cursor/CURSOR-EXECUTION-ORDER.md`
7. `cursor/CURSOR-MASTER-PROMPT.md`
8. `cursor/STOP-RULES.md`
9. `cursor/work-packages.json`
10. `cursor/execution-units.json`
11. `cursor/VERIFICATION-PROMPTS.md`

Give Cursor the complete content of `cursor/CURSOR-MASTER-PROMPT.md` before starting implementation.

## Exact Work Package order

The safest deterministic execution order is the following. Cursor must still verify dependencies before each package instead of relying only on the row number.

| Order | Work Package | Title | Required dependencies |
|---:|---|---|---|
| 1 | `WP-000` | Baseline integrity and authority | None |
| 2 | `WP-010` | Pin and lock the complete toolchain | `WP-000` |
| 3 | `WP-020` | Monorepo build and generated-contract pipeline | `WP-010` |
| 4 | `WP-030` | PostgreSQL clean install, upgrade, RLS, and invariants | `WP-020` |
| 5 | `WP-040` | Identity, authorization, tenant context, and audit | `WP-030` |
| 6 | `WP-045` | Durable WebSocket Event Relay and service event clients | `WP-040` |
| 7 | `WP-050` | Secure file lifecycle and object storage | `WP-040`, `WP-045` |
| 8 | `WP-060` | Deterministic pricing, quote, and margin engine | `WP-040`, `WP-045` |
| 9 | `WP-070` | Task admission, revision, reservation, and submission | `WP-050`, `WP-060` |
| 10 | `WP-080` | Worker enrollment, device trust, consent, and readiness | `WP-040`, `WP-045` |
| 11 | `WP-090` | Model registry, license gate, signed distribution, and rollback | `WP-050`, `WP-080` |
| 12 | `WP-100` | Router, automatic lease, retry, and fencing | `WP-070`, `WP-080`, `WP-090` |
| 13 | `WP-110` | Android Worker execution runtime | `WP-090`, `WP-100` |
| 14 | `WP-120` | Result intake, verification, consensus, and human review | `WP-100`, `WP-110` |
| 15 | `WP-130` | Usage, billing, ledger, reward, and reconciliation | `WP-060`, `WP-120` |
| 16 | `WP-140` | Webhooks and notifications | `WP-070`, `WP-130` |
| 17 | `WP-150` | Customer portal production implementation | `WP-040`, `WP-045`, `WP-070`, `WP-130`, `WP-140` |
| 18 | `WP-160` | Operations portal and controlled administrative actions | `WP-120`, `WP-130` |
| 19 | `WP-170` | Stripe billing, tax, KYC, and payout adapters | `WP-130` |
| 20 | `WP-180` | Fraud, abuse, privacy, and security automation | `WP-120`, `WP-170` |
| 21 | `WP-190` | AWS primary/DR infrastructure and Kubernetes platform | `WP-010`, `WP-045` |
| 22 | `WP-200` | CI/CD, artifact signing, provenance, and release automation | `WP-020`, `WP-190` |
| 23 | `WP-210` | Capacity, performance, reliability, and unit economics | `WP-130`, `WP-190` |
| 24 | `WP-220` | Independent security verification and penetration closure | `WP-180`, `WP-200` |
| 25 | `WP-230` | Backup, restore, regional disaster recovery, and operational game days | `WP-190`, `WP-200` |
| 26 | `WP-240` | Legal, privacy, finance, model-license, and commercial approvals | `WP-170`, `WP-220` |
| 27 | `WP-250` | Production canary, reconciliation, and final release | `WP-210`, `WP-220`, `WP-230`, `WP-240` |

## Dependency-aware parallelism

The canonical selection rule prefers the lowest-numbered ready package. A team may run independent branches in parallel only when all of the following are true:

- all dependencies of each branch are complete;
- the packages do not overlap `allowedPaths`;
- each branch uses a separate working tree or branch;
- generated contracts and shared manifests are not modified concurrently;
- both branches rerun full regression validation after merge.

Important ready branches include:

- After `WP-045`: `WP-050`, `WP-060`, `WP-080`, and `WP-190` may become independently eligible.
- After `WP-130`: `WP-140`, `WP-160`, `WP-170`, and `WP-210` may become independently eligible when their other dependencies are complete.
- After `WP-200`: `WP-230` may proceed independently from `WP-220` when its dependencies are complete.

When there is any doubt, use the strict sequential order in the table.

## Required execution cycle for every Work Package

For each Work Package, Cursor must perform this exact cycle:

1. Read the package entry in `cursor/work-packages.json`.
2. Verify all declared dependencies and their evidence.
3. List the package `allowedPaths`, required outputs, acceptance criteria, commands, and evidence path.
4. Find all package execution units in `cursor/execution-units.json`.
5. Select only one not-yet-complete execution unit.
6. Read every contract, schema, sample, state machine, migration, and invariant referenced by that unit.
7. Modify only the unit and Work Package `allowedPaths`.
8. Implement production behavior and negative paths; do not stop at interfaces, scaffolding, mocks, or TODOs.
9. Add or update unit, integration, concurrency, security, and contract tests required by the unit.
10. Run the execution-unit verification commands exactly as declared.
11. Fix all repository-owned failures without weakening tests or contracts.
12. Repeat steps 5 through 11 until every execution unit in the Work Package is complete.
13. Run all Work Package verification commands exactly as declared.
14. Run repository regressions:

```bash
bash tools/validate_all.sh
python tools/validate_traceability.py
python tools/validate_cursor_plan.py
```

15. Generate machine-readable evidence only after every required command exits zero.
16. Bind evidence to the current commit and artifact hashes where supported.
17. Update `cursor/project-state.json` only after evidence is valid.
18. Commit the Work Package as an isolated, reviewable change.
19. Run the matching independent verification prompt from `cursor/VERIFICATION-PROMPTS.md`.
20. Select the next lowest-numbered ready Work Package.

## Mandatory verification checkpoints

Use the prompts in `cursor/VERIFICATION-PROMPTS.md` at these points:

| Checkpoint | Required prompt |
|---|---|
| Before `WP-000` | Prompt 1 — Baseline Package Verification |
| After every Work Package | Prompt 2 — Per-Work-Package Verification |
| After `WP-100` | Prompt 3 — Auto-Assignment Verification |
| After `WP-110` and `WP-120` | Prompt 3 again, against the integrated runtime and result path |
| Before `WP-250` | Prompt 1 again plus Prompt 2 for every completed Work Package |
| After `WP-250` | Prompt 4 — Final Repository and Production Gate Verification |

## Critical Auto-Assignment rule

The Worker gives global consent through current consent plus `Available` status. The system automatically assigns compatible tasks.

The implementation must never introduce:

- a per-task Accept button;
- a per-task Reject button;
- an assignment offer state;
- an assignment acceptance API or event;
- an acceptance timeout;
- Worker-user confirmation before execution.

WebSocket ACK is transport receipt only. It is never Worker consent.

## Failure and stop behavior

Cursor must stop the current package and report a blocker when:

- a declared dependency is incomplete;
- authoritative contracts contradict each other;
- a required external credential, signature, approval, environment, or device is unavailable;
- a verification command cannot run and no repository-owned repair can make it run;
- completing the package would require modifying forbidden paths;
- evidence cannot be tied to real output;
- a security, financial, tenant-isolation, ledger, fencing, or durability invariant would be weakened.

Cursor must not:

- mark a Work Package complete with failing or skipped tests;
- manufacture cloud, legal, security, DR, attestation, or deployment evidence;
- edit generated output manually when a generator exists;
- bypass PostgreSQL RLS or workspace authorization;
- use floating point for money;
- acknowledge a durable event before transaction commit;
- accept stale fence-token results;
- add another database, message broker, or distributed cache.

## Completion definition

Implementation is not complete merely because all 27 Work Packages are marked complete.

Final completion requires:

1. Every package acceptance criterion is proven.
2. Every required command exits zero.
3. Every execution unit has traceable implementation and tests.
4. All internal evidence is bound to the exact repository state.
5. All required external evidence is genuine and signed where required.
6. `python tools/production_gate.py` passes against the exact release commit and artifacts.
