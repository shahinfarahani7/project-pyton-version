# FibonAI — Business Analyst Brief

| Field | Value |
| --- | --- |
| **Document type** | Explainable product & process overview |
| **Audience** | Business analysts, product owners, compliance reviewers, partners |
| **Product brand** | FibonAI (public) |
| **Platform name (internal)** | EdgeMint |
| **Version** | 1.0 |
| **Date** | 2026-10-28 |
| **Source of truth for conflicts** | [EDGE-MINT-TARGET-ARCHITECTURE-v2.md](../EDGE-MINT-TARGET-ARCHITECTURE-v2.md), [production/canonical-decisions.yaml](../../production/canonical-decisions.yaml) |
| **Companion (technical summary)** | [PROJECT-OVERVIEW.md](../PROJECT-OVERVIEW.md) |
| **Persian (فارسی)** | [FibonAI-Business-Analyst-Brief.fa.md](FibonAI-Business-Analyst-Brief.fa.md) · PDF: `FibonAI-Business-Analyst-Brief.fa.pdf` |

---

## 1. Purpose of this document

This brief explains **what FibonAI is as a business**, **who uses it**, **how work and money flow**, and **which rules are fixed** for the first commercial release (GA1). It is written for analysis work: requirements traceability, process models, stakeholder interviews, gap analysis, and compliance review.

It does **not** replace legal terms, the full architecture specification, or signed production evidence.

---

## 2. Executive summary

FibonAI is a **B2B AI execution platform** with a distinctive commercial model:

1. The customer **sees a fixed price in euros before any task runs** (“quote before run”).
2. Work is executed **preferentially on opted-in mobile devices** (edge workers), not only in a central cloud.
3. If edge capacity or policy blocks execution, **cloud fallback is explicit** — reason and cost are recorded; there is no silent reroute.
4. **Every step is auditable** for regulated teams (assignments, verification, billing, rewards, fallback).

**Positioning (phase 1 messaging):** edge-first AI inference with transparent pricing and auditable execution — not cryptocurrency mining, not guaranteed worker income, not token investment.

---

## 3. Business problem and value

### 3.1 Customer problem

Organizations need document, vision, and language AI (OCR, extraction, classification, summarization, moderation) without:

- Surprise bills after jobs complete
- Opaque routing (“where did my data go?”)
- Weak audit trails for finance or compliance reviews

### 3.2 Customer value

| Value | How FibonAI delivers it |
| --- | --- |
| **Price certainty** | Immutable EUR quote before confirmation; published unit rates as baseline |
| **Policy control** | Region / execution policies enforced at intake; cloud only when policy allows |
| **Auditability** | Hash-chained ledger of task lifecycle, verification, billing, and fallback events |
| **Integration** | REST API, webhooks, customer portal; async task lifecycle |

### 3.3 Worker (supply-side) value

Phone owners who **opt in** can contribute device compute to assigned tasks within limits they set (battery, Wi‑Fi, thermal). They receive **variable EUR rewards** (not tokens in GA1), subject to identity/payout eligibility.

### 3.4 Operator value

Internal teams run routing, fraud review, reconciliation, worker support, billing disputes, and incident response through an **operations console**, with the same ledger the customer audit uses.

---

## 4. Stakeholders and personas

| Stakeholder | Persona examples | Primary goals |
| --- | --- | --- |
| **Customer organization** | Finance ops, integration engineer, compliance officer | Submit work, control cost, prove who ran what and where |
| **Customer user** | Portal user uploading invoices | Simple upload → quote → result |
| **Worker** | Android app user | Control when device works; understand rewards are not guaranteed |
| **Operator** | Support, fraud, finance, SRE | Resolve failures, reconcile payouts, enforce policy |
| **Payment / identity providers** | Stripe Billing, Stripe Connect, Stripe Identity | Bill customers; pay workers where supported |
| **Regulator / auditor (external)** | Customer’s auditor | Evidence of policy, pricing, and data handling |

**Trust boundaries (for requirements):**

- Customer input is **untrusted** until validated.
- Worker device and worker-submitted results are **untrusted** until server verification.
- Customer **identity is not shown** to workers; task payloads are ephemeral (inputs deleted within **15 minutes** per architecture policy).

---

## 5. Core business capabilities (GA1 scope)

Aligned with [system-scope.md](../00-executive/system-scope.md) and canonical GA1 scope:

| Capability area | In GA1 | Notes for BA |
| --- | --- | --- |
| Marketing site & developer docs | Yes | Public FibonAI brand |
| Customer org / workspace / API keys | Yes | Workspace-scoped tenancy |
| Async task API + files + webhooks | Yes | Idempotent create patterns |
| Task catalog (OCR, docs, vision, NLP, etc.) | Yes | **56 catalog types**; not all have unique on-device handlers yet |
| Worker app (Android-first) | Yes | Consent, earnings UI, gamification (no gambling mechanics) |
| Edge-preferred routing + cloud fallback | Yes | Fallback must be recorded |
| EUR billing (credits, subscriptions, invoices) | Yes | Micro-EUR integer money |
| EUR worker rewards (off-chain) | Yes | Stripe Connect; country gating |
| Operations console | Yes | Audit, fraud, reconciliation |
| Public token sale / on-chain settlement | **No** | Explicitly excluded GA1 |
| Permissionless model publishing | **No** | Approved catalog only |
| Training on worker devices | **No** | Inference only |
| Multi-phone split of one inference | **No** | |
| Hidden background compute | **No** | Foreground / visible execution on Android |

**Token claims:** Architecture documents describe gated token concepts for **future** phases. **GA1 canonical decision: token features disabled** — rewards and billing are **EUR liabilities only**. Do not specify token value, investment, or “earn crypto” in GA1 materials.

---

## 6. End-to-end business process — “Run one AI task”

Use this as the baseline **happy path** for swimlanes, user stories, and acceptance criteria.

### 6.1 Swimlane summary

| Step | Customer | Platform (control plane) | Worker device | Finance / ledger |
| --- | --- | --- | --- | --- |
| 1 | Submit task + input file | Validate input & policy | — | — |
| 2 | Receive **quote** (EUR, route, policy hash) | Price from PriceBook + modifiers | — | — |
| 3 | Confirm task | Lock quote; enter scheduling | — | — |
| 4 | — | Select eligible worker; reserve capacity; create **lease + fence** | Receive **assignment** (signed) | — |
| 5 | Optional progress via portal/webhook | Track lifecycle events | Execute if consent & safety OK | — |
| 6 | — | **Verify** result (tiers: standard → consensus → human) | Submit result / failure evidence | — |
| 7 | Receive result | Deliver webhook / portal | — | Bill customer once; credit worker once |
| 8 | — | If edge unavailable and policy allows: **cloud fallback** with recorded reason | — | Incremental cost recorded |

### 6.2 Business rules (must hold in requirements)

| ID | Rule | Rationale |
| --- | --- | --- |
| BR-01 | Quote is **immutable** after issuance until expiry | “Price first” promise |
| BR-02 | **Only the platform** schedules, retries, reassigns, and decides cloud fallback | Prevents worker-side orchestration and fraud |
| BR-03 | Worker **does not accept/reject** individual tasks in production protocol | Opt-in + availability is the consent model |
| BR-04 | **Exactly one** accepted completion and **one** customer charge per task revision | Billing integrity |
| BR-05 | **Exactly one** reward credit per accepted worker contribution (per policy) | Payout integrity |
| BR-06 | Cloud fallback **never silent** | Compliance and customer trust |
| BR-07 | Worker rewards are **variable, not guaranteed** | Legal / worker terms |
| BR-08 | Platform is **not crypto mining** | Worker terms and marketing guardrails |
| BR-09 | Temporary customer inputs **deleted within 15 minutes** | Privacy by design |
| BR-10 | GA1: **no token** sale, value, or investment claims | [canonical-decisions.yaml](../../production/canonical-decisions.yaml) |

### 6.3 Exception paths (BA should model)

| Exception | Expected platform behavior | Customer-visible outcome |
| --- | --- | --- |
| No eligible worker | Queue, retry, or cloud fallback (if policy allows) | Delay or fallback with reason |
| Worker loses consent mid-run | Pause / terminate; server reassigns or fails | Task state + audit event |
| Verification fails | Retry classification per policy; escalation tiers | Failed or escalated status |
| Quote expired before confirm | Reject confirm; new quote required | Clear error |
| Unsupported worker country | Earning disabled for worker; task may still run on other workers | N/A to customer |
| Duplicate submission (idempotency) | Same logical task identity | No double bill |

---

## 7. Product catalog (business view)

Customers choose a **task type** (from catalog). Examples aligned with marketing and published pricing:

| Category | Example task types | Typical input | Published example rate (baseline) |
| --- | --- | --- | --- |
| Document intelligence | Document OCR, structured extract, verify | PDF, image | OCR from **€0.0025 per page** (final quote adds modifiers) |
| Vision & catalog | Image classify, tagging, safety checks | Image | e.g. **€0.0015 per image** (classify) |
| Language & NLP | Summarize, translate, moderate | Text | e.g. **€0.003 per 1k chars** (translate) |

**Important for BA:**

- Catalog lists **56 types**; implementation maps many types onto shared **pipelines** on the worker (OCR + on-device LLM + vision).
- **Published rates** are starting points; quotes include plan, priority, verification tier, and execution policy.
- **Accuracy** of OCR on real-world receipts is a **separate acceptance** from “API returns valid JSON.”

---

## 8. Commercial model

### 8.1 Customer side

| Element | Description |
| --- | --- |
| Currency | **EUR only** |
| Money precision | Integer **micro-EUR** (no floating point in core ledger) |
| Pricing engine | PriceBook (e.g. public EUR 2026 Q3 v2 referenced on site) + quote modifiers |
| Billing rails | Stripe Billing; tax via Stripe Tax |
| Prepaid | Compute credits (non-transferable prepaid balance) |

### 8.2 Worker side

| Element | Description |
| --- | --- |
| Reward unit | EUR micros (**Reward Micros** — not a token, not transferable) |
| Payout | Stripe Connect Express after KYC (Stripe Identity) |
| Unsupported countries | Worker earning **disabled**; no manual bypass |
| Messaging | Must not promise guaranteed income or passive investment returns |

### 8.3 What not to specify in GA1 sales copy

- Token price, APY, “invest in the network,” or referral earnings from others’ tasks
- Guaranteed worker earnings or mining metaphors
- Total job price unless computed from **published** unit rate × measurable quantity on a real quote

---

## 9. Verification and quality (business tiers)

Verification is a **product knob** affecting price and SLA:

| Tier (concept) | Business meaning |
| --- | --- |
| Standard | Single verified result path |
| Consensus | Multiple independent workers; anti-affinity rules |
| Human review | Escalation when automated verification insufficient |

Requirements should tie **verification choice** to **quote line items** and **audit events**.

---

## 10. Channels and touchpoints

| Channel | User | Primary actions |
| --- | --- | --- |
| Customer portal | Business user | Create task, view quote, monitor status, audit |
| REST API | Integration | Idempotent create, quote, lifecycle, webhooks |
| Worker mobile app | Worker | Opt-in, availability, run assigned work, view earnings |
| Operations portal | Internal staff | Investigate tasks, workers, fraud, billing |
| Marketing site | Prospect | Positioning, waitlist, pricing table (published rates) |
| Webhooks / SSE | Customer systems | Event-driven integration |

---

## 11. Compliance and messaging guardrails

Use this checklist when reviewing user stories, copy, or partner decks:

- [ ] Quote shown **before** run confirmation
- [ ] Fallback reason and cost **visible** when cloud used
- [ ] Worker copy includes **variable / not guaranteed** rewards
- [ ] No **token investment** or **mining** language in GA1
- [ ] Money shown as **EUR strings** from published or quoted amounts
- [ ] Data residency / region policy described where relevant
- [ ] DPA, privacy, worker participation terms referenced for legal sign-off (see `docs/09-legal/`)

---

## 12. Implementation status (for planning, not for customer promises)

| Topic | Statement for BA planning |
| --- | --- |
| Target architecture | Complete and frozen (v2) |
| Codebase & plan | Large implementation present; plan TODO marks phases complete (2026-09-13) |
| **Production certification** | **Not complete** — production gate requires live environment evidence |
| Live OCR quality | **Not business-certified** on real receipts |
| Real-time worker delivery | Target WebSocket; verify actual worker transport before SLA claims |
| Public launch | Marketing/waitlist assets exist; GA1 gates remain |

Treat customer-facing SLAs as **blocked** until production gate and agreed UAT sign-off.

---

## 13. Glossary (business language)

| Term | Business meaning |
| --- | --- |
| **Task** | Customer’s request to run one unit of AI work (stable identity) |
| **Revision** | Immutable version of inputs/settings for that task |
| **Quote** | Fixed EUR price + route + policy hash, valid until expiry |
| **Policy hash** | Fingerprint of execution policy for audit/replay |
| **Assignment** | Platform’s instruction for one worker to execute one attempt |
| **Lease / fence** | Exclusive right to execute; fence prevents stale workers overwriting results |
| **Verification** | Platform decision that result meets quality/integrity rules |
| **Cloud fallback** | Running on approved cloud when edge cannot meet policy/SLA |
| **Compute credit** | Customer prepaid EUR balance (non-transferable) |
| **Reward micros** | Worker payable EUR amount (liability), not a tradable token |
| **Workspace** | Customer tenancy boundary for data and billing |
| **Edge / worker** | Opted-in device executing signed models |
| **GA1** | First commercial release scope per canonical decisions |

Full definitions: [glossary.md](../00-executive/glossary.md).

---

## 14. Suggested BA deliverables from this brief

| Deliverable | Suggested content |
| --- | --- |
| **Context diagram** | Customer, Worker, Operator, Stripe, Cloud provider |
| **BPMN** | §6 happy path + §6.3 exceptions |
| **Stakeholder map** | §4 + RACI for quote, fallback, payout |
| **Requirements backlog** | Trace BR-01…BR-10 to epics |
| **Data dictionary** | Task, Quote, Assignment, Result, Ledger event |
| **Compliance matrix** | Map BR rules to legal docs in `docs/09-legal/` |

---

## 15. Related documents

| Document | Use when |
| --- | --- |
| [PROJECT-OVERVIEW.md](../PROJECT-OVERVIEW.md) | Shorter technical + repo map |
| [EDGE-MINT-TARGET-ARCHITECTURE-v2.md](../EDGE-MINT-TARGET-ARCHITECTURE-v2.md) | Deep scheduling, failure, reward mechanics |
| [system-scope.md](../00-executive/system-scope.md) | In/out of scope list |
| [docs/02-product/](../02-product/) | Portal, worker, task lifecycle specs |
| [docs/01-business/](../01-business/) | Pricing, revenue, GTM |
| [docs/09-legal/](../09-legal/) | Terms, DPA, GA1 approval register |

---

## 16. Document history

| Version | Date | Author | Change |
| --- | --- | --- | --- |
| 1.0 | 2026-10-28 | Prepared from PROJECT-OVERVIEW + canonical scope | Initial BA brief |
