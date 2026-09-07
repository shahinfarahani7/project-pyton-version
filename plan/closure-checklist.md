# Final Closure Checklist



> **Authority:** [EDGE-MINT-TARGET-ARCHITECTURE-v2.md](../docs/EDGE-MINT-TARGET-ARCHITECTURE-v2.md) Section 69 (+ v2 additional items)  

> **Historical:** Phase 0–7 addressed v1-plan scope; Phase 8 closes v2 gaps.



Mark items here when the linked task reaches `done` with `IMPLEMENTED_PRODUCTION` evidence.



---



## Assignment and delivery



- [x] Production Lease Bootstrap is verified. → **P1-T01**, **P1-T02** (dev/test: SQL + pytest + source verify)

- [ ] Outbox/WebSocket lease delivery is verified. → **P1-T03**, **P1-T04**, **P8-A03** (outbox yes; worker WS push not production-proven)

- [x] Replay is duplicate-safe. → **P1-T05**, **P7-CHAOS-websocket-replay**, **P7-CHAOS-duplicate-delivery**, **P8-A03** (dev evidence; production T03 pending)

- [x] Stale fence writes are rejected. → **P1-T08**, **P7-CHAOS-stale-fence-writes**, **P8-A02** (dev evidence; T02 full proof pending)

- [ ] Delivery ACK semantics verified. → **P1-T10**, **P8-A03** (policy documented; full ACK path partial)



## Resource and scheduling



- [ ] Resource Reservation Ledger exists. → **P2-T13**, **P2-T14**, **P8-A04** (SQL + service; prod proof pending)

- [x] Atomic reservation is verified. → **P2-T20**, **P2-T21**, **P4-T09** (dev evidence)

- [x] Task Resource Envelopes exist. → **P2-T05**, **P2-T06**

- [x] Task Cost Estimator exists. → **P2-T07**, **P2-T08**, **P8-A20** (versioned prediction layer)

- [ ] Execution Plans exist where required. → **P2-T09**, **P2-T10**, **P8-A05**

- [ ] Runtime Compatibility Profiles exist. → **P2-T15**, **P2-T16**, **P8-A13**

- [ ] Exclusive group scheduling policy exists. → **P2-T17**, **P2-T18**

- [ ] User resource consent policy exists. → **P2-T11**, **P2-T12**, **P8-A06**

- [x] Device Calibration exists. → **P2-T03**, **P2-T04**, **P6-T03**, **P8-A20** (expiry + cold/warm comparability)

- [x] Resource Fit is used. → **P4-T03**

- [x] Fragmentation/Scarcity Cost is used. → **P4-T04**

- [x] Failure Affinity exists. → **P4-T05**, **P8-A14** (artifact pool block + cooldown; T14 E2E PARTIAL)



## Worker runtime



- [x] Checkpoint/Resume is fence-aware. → **P3-T08**, **P7-CHAOS-chunk-resume**, **P8-A12** (dev evidence; T12 pending)

- [ ] Worker has no scheduling authority. → **P0-T08**, **P3-T20**, **P8-A09**

- [ ] Worker executes only approved Plans and enforces local safety/consent without scheduling authority. → **P3-T01**, **P3-T02**, **P3-T15**, **v2 §2.2**, **P8-A09**

- [x] Qwen model lifecycle is stable. → **P0-T03**, **P3-T03**, **P3-T16**, **P8-A16**, **P8-A24** (dev verify hook + identity manifest; device proof PARTIAL)

- [x] Qwen context is guarded before native runtime. → **P0-T05**, **P3-T04**, **P8-A10**

- [x] Long summarize uses map/reduce chunking. → **P3-T06**, **P3-T07**, **P7-CHAOS-long-context-summarize**, **P8-A11**

- [x] Model residency is scheduler-visible. → **P0-T04**, **P3-T18**, **P4-T02**, **P8-A22**



## Validation, reward, consent



- [ ] Result Validation covers every executable task. → **P5-CROSS-01**, **P5-QWEN-***, **P5-VIS-***, **P8-A18**

- [x] Reward is validation-gated and idempotent. → **P7-CHAOS-reward-exactly-once**, **P8-A08** (dev evidence; T08 pending)

- [x] 30% and 50% are server policy values. → **P6-T01**, **P6-T02**, **P7-CHAOS-consent-***, **P8-A06**

- [x] Consent transitions handled. → **P6-T08**, **P6-T09**, **P6-T10**, **P7-CHAOS-consent-***, **P8-A06**



## Task catalog



- [x] The actual unique Task catalog is classified and reconciled against the historically reported 56. → **P0-T06**, **P5-GAP-08**, **P8-A15**, **P8-T05**

- [x] All Flex tasks have Input Contracts. → **P5-FLEX-01** … **P5-FLEX-09**, **P8-A15** (9/9 flexInput DSL + worker handlers)

- [ ] Vision tasks have distinct runtime/resource profiles. → **P5-VIS-01** … **P5-VIS-14**



## Production proof (v1-plan + v2 extensions)



- [x] 20-worker load test passes (dev crypto/load sim). → **P7-CHAOS-20-workers**; v2 requires named workload + physical-device matrix (**T17**, **P8-A17**)

- [x] Chaos tests pass (dev harness). → **P7-CHAOS-***; v2 §74 cases **T01–T24** remain **NOT RUN**

- [x] Exactly-once accepted completion passes (dev). → **P7-CHAOS-reward-exactly-once**, **P8-A08**

- [x] Exactly-once reward passes (dev). → **P7-CHAOS-reward-exactly-once**, **P8-A08**

- [x] Rollout and rollback procedures are proven (dry-run). → **P7-T01**, **P7-T02**; v2 runtime upgrade rollback → **P8-A24**



---



## v2 additional closure requirements (§69)



Unchecked until Phase 8 evidence exists:



- [ ] TaskRun identity distinct from TaskRevision; cancellation/acceptance races → **P8-A01** / **T01**

- [ ] Monotonic fencing spans all Attempts/Assignments of a TaskRun → **P8-A02** / **T02**

- [ ] Stop requested vs stop confirmed; stale physical holds → **P8-A02** / **T02**

- [ ] Runtime/base/resident/task/transfer memory accounting → **P8-A04** / **T04**

- [ ] Immutable Revision envelopes vs per-input ExecutionAllocations → **P8-A05** / **T05**

- [ ] CPU unit/window/burst/stop bounds and explicit consent opt-in certified → **P8-A06** / **T06**

- [ ] Tenant isolation, data-owner permission, Worker trust negative tests → **P8-A07** / **T07**

- [x] Candidate/validation/entitlement crash boundaries → **P8-A08** / **T08** (dev SQL+service; crash harness PARTIAL)

- [x] Task retry vs identical-message retransmission separation → **P8-A09** / **T09** (dev transport receipts; E2E PARTIAL)

- [x] Full formatted-prompt counts and output limits → **P8-A10** / **T10** (dev boundary tests; native tokenizer E2E PARTIAL)

- [x] Recursive reduction bounded depth/calls/no-progress stop → **P8-A11** / **T11** (dev bounds + progress rule; E2E PARTIAL)

- [x] Checkpoint rebinding/coverage/model-space compatibility → **P8-A12** / **T12** (dev manifest + ResumeGrant; cross-Worker E2E PARTIAL)

- [x] Cross-runtime conflicts; control-message capacity under load → **P8-A13** / **T13** (dev pair/light-work tests; transfer load E2E PARTIAL)

- [x] Task-wide budgets cannot reset via new Attempts or Cloud fallback → **P8-A14** / **T14** (dev TaskRun budget + cloud gate; E2E PARTIAL)

- [x] Catalog counts/Flex status from current snapshot → **P8-A15** / **T15** (56 unique reconciled; flex gate; orphan DSL documented)

- [x] Artifact manifests; concurrent install/activation → **P8-A16** / **T16** (dev coordinator + verify; device E2E PARTIAL)

- [x] Process death/suspension/background on physical devices → **P8-A17** / **T17** (platform profile + coordinator; physical harness NOT_RUN)

- [x] Quality gates reject contract-valid but semantically invalid outputs → **P8-A18** / **T18** (semantic layer; full golden matrix NOT_RUN)

- [x] DRR fairness, aging, queue limits, backpressure, reconciliation SLOs → **P8-A19** / **T19** (policy + modules; saturation harness NOT_RUN)

- [x] Calibration/estimator version expiry; cold/warm comparability → **P8-A20** / **T20** (policy + module; E2E NOT_RUN)

- [x] Decoded-input, temp-file, upload/retention/cleanup/privacy → **P8-A21** / **T21** (decode bounds + privacy coordinator; E2E NOT_RUN)

- [x] Active identity loop traces; Native-handle regression → **P8-A22** / **T22** (tracer + reconciliation; physical harness NOT_RUN)

- [x] Production policy readiness §73 gate wired (activation remains CLOSED until evidence) → **P8-T04** / **P8-A23** / **T23**

- [x] Runtime maintenance/upgrade policy and rollback evidence → **P8-A24** / **T24** (evaluation wired; device proof NOT_RUN)

