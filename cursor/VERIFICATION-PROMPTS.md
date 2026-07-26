# EdgeMint Verification Prompts

## How to use this file

These prompts are designed for an independent Cursor verification pass. The verifier must inspect and execute the actual repository. It must not trust completion flags, previous reports, generated summaries, or claimed test results without reproduction.

Recommended order:

1. Run Prompt 1 before `WP-000`.
2. Run Prompt 2 after every Work Package, replacing `<WP_ID>` with the actual package ID.
3. Run Prompt 3 after `WP-100`, then again after `WP-110` and `WP-120`.
4. Run Prompt 4 after `WP-250` and before declaring the release production certified.

---

# Prompt 1 — Baseline Package Verification

```text
You are the independent baseline verifier for the EdgeMint v5.0 repository.

Your job is to verify the repository as it actually exists. Do not trust previous audit reports, readiness scores, generated summaries, manifests, or claims unless you independently reproduce their evidence.

Read these files first:

- START-HERE.md
- README.md
- production/canonical-decisions.yaml
- production/AUTO-ASSIGNMENT-PROTOCOL.md
- production/WEBSOCKET-EVENT-RELAY-ARCHITECTURE.md
- production/DEFINITION-OF-PRODUCTION-READY.md
- production/AMBIGUITY-REGISTER.md
- cursor/CURSOR-EXECUTION-ORDER.md
- cursor/CURSOR-MASTER-PROMPT.md
- cursor/STOP-RULES.md
- cursor/work-packages.json
- cursor/execution-units.json
- cursor/project-state.json
- PACKAGE-MANIFEST.json
- CHECKSUMS.sha256

Perform the following work:

1. Confirm that the package version is consistently 5.0.0.
2. Verify the package manifest and every checksum against the actual files.
3. Verify that no obsolete v4.0 authoritative artifact is being used.
4. Verify that the repository contains no unresolved authoritative contradiction.
5. Verify that all JSON, YAML, DSL, OpenAPI, AsyncAPI, CloudEvent, SQL and evidence schemas are structurally valid.
6. Verify that all OpenAPI operations have matching operation contracts, samples, execution units and traceability records.
7. Verify that every Work Package has:
   - valid dependencies;
   - allowed paths;
   - required outputs;
   - acceptance criteria;
   - executable verification commands;
   - an evidence path.
8. Verify that no generated report is being used as a substitute for actual implementation or test evidence.
9. Search the repository for:
   - TODO;
   - FIXME;
   - NotImplementedException;
   - placeholder;
   - stub;
   - fake production evidence;
   - skipped or ignored tests;
   - hard-coded credentials;
   - untracked dependency versions;
   - obsolete Offer/Accept/Reject assignment behavior.
10. Run, without skipping or weakening any command:

python tools/verify_package.py
bash tools/validate_all.sh
python tools/validate_production_pack.py
python tools/validate_cursor_plan.py
python tools/validate_traceability.py
python tools/validate_release_blockers.py

When a repository-owned issue is found, fix it within the authoritative repository scope and rerun every affected validation command.

Do not fabricate or replace external credentials, approvals, signatures, cloud evidence, penetration-test results, disaster-recovery evidence or production deployment evidence.

Stop and report a blocker when a required external input is genuinely unavailable.

Produce a final report with exactly these sections:

1. Package identity
2. Files inspected
3. Commands executed with actual exit codes
4. Contract and traceability findings
5. Stub and placeholder findings
6. Auto-assignment compatibility findings
7. Changes made
8. Remaining internal gaps
9. Missing external evidence
10. Final verdict

The final verdict must be one of:

- BASELINE PASS
- BASELINE FAIL
- BLOCKED BY EXTERNAL INPUT

Do not report BASELINE PASS unless all required commands exit zero and no unresolved internal gap remains.
```

---

# Prompt 2 — Per-Work-Package Verification

Replace `<WP_ID>` with the package being verified, for example `WP-100`.

```text
Act as the independent implementation verifier and remediator for EdgeMint Work Package `<WP_ID>`.

Do not assume the Work Package is complete because its code exists or because another agent marked it complete.

Read the authoritative Work Package definition from:

- cursor/work-packages.json

Then identify every execution unit belonging to `<WP_ID>` from:

- cursor/execution-units.json

Also read:

- cursor/CURSOR-EXECUTION-ORDER.md
- cursor/CURSOR-MASTER-PROMPT.md
- cursor/STOP-RULES.md
- production/canonical-decisions.yaml
- production/AUTO-ASSIGNMENT-PROTOCOL.md
- production/WEBSOCKET-EVENT-RELAY-ARCHITECTURE.md
- database/README.md
- cursor/project-state.json

Perform the verification in this order:

1. Dependency verification
   - Confirm every declared dependency is complete.
   - Confirm its evidence file exists.
   - Confirm the evidence belongs to the current repository state and has not been copied from another commit.
   - Do not continue when a dependency is incomplete.

2. Scope verification
   - List the Work Package allowedPaths.
   - Inspect the actual changes.
   - Report and revert or correct unauthorized changes outside allowedPaths unless an authoritative dependency explicitly permits them.

3. Required-output verification
   - Verify every required output exists as working implementation.
   - Do not accept interfaces, empty handlers, placeholder responses, mocked production paths, TODOs or scaffolding as completed output.

4. Execution-unit verification
   For every execution unit belonging to `<WP_ID>`:
   - verify the implementation target exists;
   - verify the test target exists;
   - verify request and response contracts;
   - verify authorization and workspace scope;
   - verify idempotency behavior;
   - verify transaction boundaries;
   - verify required writes;
   - verify domain events;
   - verify outbox atomicity;
   - verify concurrency behavior;
   - verify all declared success and error paths;
   - run every execution-unit verification command exactly as written.

5. Acceptance-criteria verification
   - Convert every acceptance criterion into a concrete check.
   - Provide file and line evidence for each criterion.
   - Mark each criterion PASS or FAIL.

6. Negative inspection
   Search all relevant paths for:
   - TODO;
   - FIXME;
   - NotImplementedException;
   - placeholder;
   - temporary mock;
   - fake adapter;
   - in-memory production repository;
   - skipped test;
   - ignored test;
   - disabled assertion;
   - catch-all success response;
   - hard-coded secret;
   - floating-point money;
   - missing workspace filter;
   - acknowledgement before transaction commit;
   - unbalanced ledger entry;
   - stale or invalid fence-token acceptance.

7. Remediation
   - Fix every repository-owned failure within the Work Package scope.
   - Add or correct tests for every repaired failure.
   - Do not weaken contracts or tests to make verification pass.
   - Do not modify generated outputs manually when a canonical generator exists.
   - Do not invent external evidence.

8. Work Package command execution
   Run every verification command declared for `<WP_ID>` in cursor/work-packages.json exactly as written.

9. Regression verification
   Run:

bash tools/validate_all.sh
python tools/validate_traceability.py
python tools/validate_cursor_plan.py

10. Evidence
   Only after every required command exits zero:
   - generate the declared machine-readable Work Package evidence;
   - bind it to the current commit and artifact hashes where supported;
   - update cursor/project-state.json;
   - mark `<WP_ID>` complete;
   - identify the next eligible Work Package.

Produce the final report with these sections:

1. Work Package
2. Dependencies
3. Execution units inspected
4. Required outputs
5. Acceptance criteria matrix
6. Commands and exit codes
7. Defects found
8. Fixes applied
9. Regression results
10. Evidence written
11. Unauthorized or out-of-scope changes
12. Remaining blockers
13. Final verdict
14. Next eligible Work Package

The final verdict must be one of:

- WORK PACKAGE PASS
- WORK PACKAGE FAIL
- BLOCKED BY DEPENDENCY
- BLOCKED BY EXTERNAL INPUT

Never report WORK PACKAGE PASS while any acceptance criterion, execution unit, required test or verification command remains incomplete or failing.
```

---

# Prompt 3 — Auto-Assignment, Worker Runtime, and Result Integrity Verification

```text
Act as the independent EdgeMint automatic-assignment, Worker-runtime and result-integrity verifier.

The canonical rule is:

A Worker gives global consent by holding current consent and setting the account to Available. Compatible tasks are assigned automatically. The system must never ask the Worker or user to accept or reject an individual task.

Inspect the actual implementation, database, contracts, events, tests, Worker application and runtime behavior. Do not trust documentation claims unless the implementation proves them.

Authoritative references:

- production/AUTO-ASSIGNMENT-PROTOCOL.md
- production/canonical-decisions.yaml
- production/WEBSOCKET-EVENT-RELAY-ARCHITECTURE.md
- cursor/work-packages.json for WP-080, WP-100, WP-110 and WP-120
- related operation contracts, OpenAPI files, AsyncAPI files, CloudEvent schemas, SQL migrations and generated clients

Verify all of the following:

## A. Forbidden Offer and confirmation behavior

Search the entire repository, including source code, database migrations, contracts, events, UI, tests, configuration and generated clients, for:

- offered
- accepted
- rejected
- acceptAssignment
- rejectAssignment
- assignment offer
- offer timeout
- acceptance timeout
- Accept Task
- Reject Task
- per-task confirmation
- user approval before execution

Distinguish unrelated natural-language uses from assignment state or behavior.

Fail verification if any per-task Accept or Reject state, API, button, event, timeout or workflow exists.

## B. Global availability

Verify that:

- Worker availability is a global account preference.
- Each device must still be online, attested, healthy, within schedule and have free capacity.
- Changing to Unavailable prevents only future leases.
- Changing to Unavailable does not cancel an existing lease.
- Existing execution continues until completion, validated machine unavailability, lease expiry or server revocation.

## C. Atomic routing and lease creation

Verify that one authoritative PostgreSQL transaction performs:

- queue claim;
- eligibility validation;
- deterministic ranking decision binding;
- Worker and device availability revalidation;
- capacity reservation;
- assignment creation;
- lease creation;
- monotonic fence-token allocation;
- TaskAttempt transition from matching to leased;
- transactional outbox insertion.

Verify concurrency tests prove that two Router instances cannot create two valid ordinary leases for the same Attempt.

Verify the transaction fails closed if any eligibility or capacity condition changes before commit.

## D. Worker selection

Verify that the Router enforces:

- current heartbeat;
- minimum trust;
- battery policy;
- thermal policy;
- network policy;
- current consent;
- Worker Available status;
- valid attestation;
- model digest;
- runtime ABI;
- region and residency restrictions;
- free capacity;
- task and model minimum tier;
- quarantine and ban status;
- deterministic scoring;
- tenant fairness;
- stale-task protection;
- retry and reassignment budgets.

Verify tie breaking is deterministic and auditable.

## E. Targeted durable delivery

Verify that:

- an assignment is sent to exactly one selected Worker device;
- ordinary assignment is never broadcast;
- durable WebSocket delivery uses PostgreSQL delivery records;
- replay and reconnect are supported;
- WebSocket ACK means transport receipt only;
- ACK is not Worker consent;
- ACK does not transition an assignment into an accepted state;
- delivery acknowledgement follows the durable protocol.

## F. Automatic start

Verify that the Worker Agent:

- validates event signature;
- validates device binding;
- validates lease identity;
- validates fence token;
- validates model digest;
- validates input digest;
- validates execution limits;
- starts execution automatically;
- does not display a confirmation prompt;
- calls reportAssignmentStarted automatically;
- continues lease renewal while execution is active.

## G. Machine-only unavailability

Verify that reportAssignmentUnavailable accepts only canonical machine-detected reasons:

- battery_low
- thermal_block
- network_policy_blocked
- model_unavailable
- insufficient_storage
- runtime_incompatible
- resource_pressure

Verify that:

- free-text reasons are rejected;
- user-selected reasons are impossible;
- the server validates the reason against trusted heartbeat, device telemetry, model state and task requirements;
- invalid or inconsistent claims are rejected and audited;
- repeated anomalous claims affect reliability or fraud signals;
- validated environmental failure does not unfairly penalize the Worker.

## H. Deadlines and reassignment

Verify:

- assignmentDeliverySeconds controls delivery time;
- autoStartGraceSeconds begins after the delivery window;
- startDeadlineAt is not earlier than deliveryDeadlineAt;
- failure to auto-start causes lease expiry or revocation;
- reassignment creates a strictly higher fence token;
- reassignment cannot continue indefinitely;
- exhausted reassignment budget causes a deterministic terminal or retry-policy transition;
- Attempts cannot remain permanently in matching.

## I. Stale and duplicate results

Verify that:

- a stale fence token cannot complete the Task;
- a stale result cannot create billing;
- a stale result cannot create Worker reward;
- stale data may only be retained as rejected evidence;
- duplicate Result submission is idempotent;
- exactly one accepted output is bound to the valid Attempt outcome.

## J. Consensus

Verify that:

- ordinary automatic assignment targets one Worker only;
- multiple Workers are used only for explicit consensus fan-out;
- consensus uses separate Attempts or assignments;
- device and account anti-affinity is enforced;
- one account cannot provide multiple independent votes;
- consensus failure transitions to retry or human review deterministically.

Execute at least these commands, plus every command declared by the affected Work Packages:

python tools/verify_vectors.py
python tools/validate_websocket_architecture.py
PYTHONPATH=src/backend python -m pytest -q src/backend/tests
cd src/apps/worker && flutter analyze && flutter test
PYTHONPATH=src/backend python -m pytest -q src/backend/tests
python tests/e2e/result_verification.py
bash tools/validate_all.sh

Create additional concurrency, negative-path and integration tests for any behavior not already proven.

Fix every repository-owned gap. Do not weaken the specification or tests. Do not fabricate device, cloud or production evidence.

Return two separate verdicts:

1. AUTO-ASSIGNMENT CONTRACT

   - PASS
   - FAIL

2. IMPLEMENTATION EVIDENCE

   - PASS
   - FAIL
   - BLOCKED BY MISSING ENVIRONMENT

Include:

- every forbidden pattern found;
- whether it was a real violation or unrelated text;
- files and lines changed;
- tests added;
- commands and actual exit codes;
- remaining external limitations.
```

---

# Prompt 4 — Final Repository and Production Gate Verification

```text
Act as the final independent release verifier for the complete EdgeMint v5.0 repository.

Do not trust prior Work Package status, evidence summaries, audit scores, release manifests, screenshots, or claimed command output. Reproduce the evidence against the exact current commit and distributable artifacts.

Perform the verification in this order:

1. Run the complete Baseline Package Verification described in Prompt 1.
2. Verify every Work Package from WP-000 through WP-250 using the rules in Prompt 2.
3. Run the complete Auto-Assignment, Worker Runtime, and Result Integrity Verification described in Prompt 3.
4. Verify that every internal evidence artifact is bound to the exact current commit, package manifest and release artifact hashes.
5. Execute all repository-owned validation, build, test, migration, contract, infrastructure, security, capacity, resilience, reconciliation and production-gate commands.
6. Verify real PostgreSQL clean-install and upgrade migration evidence.
7. Verify real Worker-device execution and attestation evidence.
8. Verify real AWS, EKS, RDS PostgreSQL, S3, KMS, networking and DR evidence.
9. Verify real load, soak, chaos, failover, backup and restore evidence.
10. Verify real penetration-test closure and security approvals.
11. Verify real legal, privacy, financial, tax, KYC, payout and model-license approvals.
12. Verify final canary, reconciliation, rollback and release-signing evidence.
13. Run `python tools/production_gate.py` against the exact release evidence set.

Do not fabricate or downgrade any missing external prerequisite into a warning.

Produce three independent verdicts:

1. INTERNAL SPECIFICATION COMPLETENESS
   - PASS
   - FAIL

2. IMPLEMENTED SYSTEM COMPLETENESS
   - PASS
   - FAIL
   - BLOCKED BY MISSING ENVIRONMENT

3. REAL PRODUCTION CERTIFICATION
   - PASS
   - FAIL
   - BLOCKED BY MISSING SIGNED EXTERNAL EVIDENCE

It is valid for the first two verdicts to pass while real production certification remains blocked by missing external evidence.

Report:

- exact commit and artifact hashes;
- every command and actual exit code;
- every Work Package verdict;
- all internal defects found and fixed;
- all unresolved internal defects;
- all missing external evidence;
- production-gate output;
- final release recommendation.

Never report production certification PASS unless the production gate passes using genuine evidence bound to the exact release artifacts.
```
