# EdgeMint Architecture Implementation Plan



> **Authority:** [docs/EDGE-MINT-TARGET-ARCHITECTURE-v2.md](../docs/EDGE-MINT-TARGET-ARCHITECTURE-v2.md) (FROZEN v2; supersedes v1)  

> **Status:** Phase 0–8 complete (218/218). v2 audit integration evidence at **IMPLEMENTED_DEV_ONLY**; §74 acceptance harnesses T12–T24 remain **NOT_RUN**; production activation gate **CLOSED**.



This folder translates the frozen target architecture (Sections 65–77) into phased, auditable work items. It complements — but does not replace — [cursor/work-packages.json](../cursor/work-packages.json).



---



## How to use



1. **Pick the next task** from [TODO.md](./TODO.md) — lowest phase number with an unblocked, unchecked item (currently **Phase 8**).

2. **Read the phase file** under [phases/](./phases/) for full task detail (objective, paths, acceptance criteria).

3. **Implement** following Section 67 (file-by-file change planning) and workspace rules in `.cursorrules`.

4. **Evidence** per Section 66: Source, SQL, Contracts, DSL, Events, Tests, Production Path.

5. **Close the task:** update [TODO.md](./TODO.md) and the task block in the phase file in the **same session** (see `.cursor/rules/architecture-plan-todo.mdc`).



---



## Phase order (dependency DAG)



```text

Phase 0 — Baseline Correction

    ↓

Phase 1 — Assignment Integrity

    ↓

Phase 2 — Resource Foundation

    ↓

Phase 3 — Worker Runtime Foundation

    ↓

Phase 4 — Scheduler Upgrade

    ↓

Phase 5 — Task Catalog Closure

    ↓

Phase 6 — Adaptive Execution

    ↓

Phase 7 — Production Proof (v1-plan scope)

    ↓

Phase 8 — v2 Audit Integration (A01–A24, §73–77)

```



Phases are sequential by default. A task may note explicit cross-phase dependencies.



---



## Task ID conventions



| Pattern | Example | Meaning |

|---------|---------|---------|

| `P{n}-T{nn}` | `P1-T03` | Phase *n*, task *nn* |

| `P5-QWEN-{nn}` | `P5-QWEN-01` | Phase 5: Qwen task closure |

| `P5-FLEX-{nn}` | `P5-FLEX-01` | Phase 5: Flex input contract |

| `P5-VIS-{nn}` | `P5-VIS-01` | Phase 5: Vision task closure |

| `P5-GAP-{nn}` | `P5-GAP-01` | Phase 5: Unresolved catalog gap |

| `P5-CROSS-{nn}` | `P5-CROSS-01` | Phase 5: Cross-cutting catalog work |

| `P7-CHAOS-{name}` | `P7-CHAOS-lease-expiry` | Phase 7: Production proof scenario |

| `P8-A{nn}` | `P8-A01` | Phase 8: v2 audit finding A01 |

| `P8-T{nn}` | `P8-T04` | Phase 8: Meta / gate tasks |



---



## Files in this folder



| File | Purpose |

|------|---------|

| [TODO.md](./TODO.md) | Master checklist — **single update surface** for progress |

| [closure-checklist.md](./closure-checklist.md) | Architecture §69 closure items mapped to task IDs |

| [audit-matrix.md](./audit-matrix.md) | Feature → `IMPLEMENTED_*` classification scaffold |

| [phases/](./phases/) | Detailed task definitions per phase |



---



## Done definition (Section 66)



A task is **done** only when classified as `IMPLEMENTED_PRODUCTION` with evidence in:



- Source code

- SQL migrations

- Contracts / OpenAPI / AsyncAPI

- DSL schemas

- Events / CloudEvents

- Tests (unit + integration where applicable)

- Verified production path (not dev-only)



Allowed gap classifications: `IMPLEMENTED_DEV_ONLY`, `TEST_ONLY`, `DOC_ONLY`, `DSL_ONLY`, `PARTIAL`, `MISSING` — document in [audit-matrix.md](./audit-matrix.md), do **not** mark TODO complete without appropriate evidence class.



---



## Architecture change control (Section 70)



v2.0 is the active frozen baseline (audit-integrated). v1 is superseded for new decisions.



Do not alter frozen core invariants (scheduling authority, lease/fence, reservation model, worker boundary, state machine, model residency, chunk strategy, reward semantics, consent ownership, validation model). Further architectural revisions require `EDGE-MINT-TARGET-ARCHITECTURE-v3.md`.



---



## Canonical principle (Section 71)



> **EdgeMint schedules centrally, executes locally, validates centrally, and protects the user locally.**

