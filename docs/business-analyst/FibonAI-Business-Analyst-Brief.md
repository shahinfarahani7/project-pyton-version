# FibonAI — Business Analyst Brief

| Field | Value |
| --- | --- |
| **Document type** | Explainable product & process overview |
| **Audience** | Business analysts, product owners, compliance reviewers, partners |
| **Product brand** | FibonAI (public) |
| **Platform name (internal)** | EdgeMint |
| **Version** | 1.1 |
| **Date** | 2026-11-17 |
| **Business model (white paper)** | [FibonAI-Business-Model.md](../business/FibonAI-Business-Model.md) — token credit, 3-phone consensus, no customer-facing prices |
| **Source of truth for engineering conflicts** | [EDGE-MINT-TARGET-ARCHITECTURE-v2.md](../EDGE-MINT-TARGET-ARCHITECTURE-v2.md), [production/canonical-decisions.yaml](../../production/canonical-decisions.yaml) |
| **Companion (technical summary)** | [PROJECT-OVERVIEW.md](../PROJECT-OVERVIEW.md) |
| **Persian (فارسی)** | [FibonAI-Business-Analyst-Brief.fa.md](FibonAI-Business-Analyst-Brief.fa.md) · PDF: `FibonAI-Business-Analyst-Brief.fa.pdf` |

---

## 1. Purpose of this document

This brief explains **what FibonAI is as a business**, **who uses it**, **how work and value flow**, and **which rules are fixed**. It is written for analysis work: requirements traceability, process models, stakeholder interviews, gap analysis, and compliance review.

It does **not** replace legal terms, the full architecture specification, or signed production evidence.

> **Two layers to keep apart.** The **business model** (from the white paper, see [FibonAI-Business-Model.md](../business/FibonAI-Business-Model.md)) uses free monthly task credit, token-backed credit and FibonAI token rewards, and **never shows prices to customers**. The **current build and frozen engineering docs** (GA1) still implement an internal EUR quote and EUR worker rewards with tokens disabled. Gaps are listed in §12 and in the business model's conflict table. Requirements for the token model need an architecture v3 revision and legal sign-off.

---

## 2. Executive summary

FibonAI is a **decentralized AI execution network** with a distinctive model:

1. Requesters get **free task requests every month**; after that they get **monthly credit with FibonAI tokens**. **No price is shown to customers** — only credits.
2. Each request gets a **quick assessment** of difficulty and time, then is sent to **at least 3 opted-in phones** (edge workers).
3. The platform **compares the answers by consensus** and returns the agreed result. Phones that answered correctly earn **FibonAI tokens**.
4. FibonAI keeps **no central store of confidential customer data**, and **every step is auditable** (assignments, validation, credits, rewards).

**Positioning:** decentralized, privacy-first AI on everyday phones — not cryptocurrency mining, not guaranteed worker income, not an investment product.

---

## 3. Business problem and value

### 3.1 Customer problem

People and organizations need document, vision, and language AI (OCR, extraction, classification, summarization, translation, photo/video edits) without:

- Expensive centralized infrastructure
- Their data being stored centrally and resold or misused
- Results they cannot trust or audit

### 3.2 Customer value

| Value | How FibonAI delivers it |
| --- | --- |
| **Free to start** | Free task requests every month; launch offer of 1 month free with a free API |
| **Simple credit** | Customers see credits left and credits used (difficulty class × base task), never a price |
| **Trusted results** | Every task is checked by at least 3 phones; only the consensus answer is returned |
| **Privacy** | No central store of confidential data; minimal payloads; encrypted transfer |
| **Auditability** | Hash-chained ledger of task lifecycle, validation, credit, and reward events |
| **Integration** | REST API, webhooks, customer portal; async task lifecycle |

### 3.3 Worker (supply-side) value

Phone owners who **opt in** (minimum 4 GB RAM and 4 GB free storage) contribute device compute to assigned tasks within limits they set (battery, Wi‑Fi, thermal). Workers whose answer matches the consensus earn **FibonAI tokens** (split rules in the business model §7). Rewards are not guaranteed.

### 3.4 Operator value

Internal teams run routing, fraud review, reconciliation, worker support, billing disputes, and incident response through an **operations console**, with the same ledger the customer audit uses.

---

## 4. Stakeholders and personas

| Stakeholder | Persona examples | Primary goals |
| --- | --- | --- |
| **Customer organization** | Finance ops, integration engineer, compliance officer | Submit work, manage credit, prove who ran what and where |
| **Customer user (public)** | Person translating a text or editing a photo | Simple upload → result, within free monthly credit |
| **Worker** | Android app user | Control when device works; earn tokens for correct tasks; understand rewards are not guaranteed |
| **Operator** | Support, fraud, finance, SRE | Resolve failures, reconcile rewards, enforce policy |
| **Treasury / governance** | Token holders above a threshold | Decide on burning, development, or reward support |
| **Parent investment company** | Founding team | Yearly allocation on the same schedule as workers |
| **Payment / identity providers** | Exchanges (DEX/CEX) for tokens; identity checks | Requesters obtain tokens; workers verified |
| **Regulator / auditor (external)** | Customer’s auditor | Evidence of policy, credit use, and data handling |

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
| Customer credit (current build: EUR credits; business model: free monthly + token credit) | Yes | Integer units only; never shown as a price |
| Worker rewards (current build: EUR off-chain; business model: FibonAI tokens) | Yes | Token rewards need architecture v3 + legal |
| Operations console | Yes | Audit, fraud, reconciliation |
| Public token sale / on-chain settlement | **No (GA1)** | Business model plans exchange listing; needs v3 + legal |
| Permissionless model publishing | **No** | Approved catalog only |
| Training on worker devices | **No** | Inference only |
| Multi-phone split of one inference | **No** | Consensus sends the **whole** task to 3+ phones; it does not split it |
| Hidden background compute | **No** | Foreground / visible execution on Android |

**Token status:** The white paper makes the FibonAI token the core of the economy (21 B fixed supply, consensus rewards). The **frozen GA1 canonical decision still disables token features**. Treat token requirements as **target scope pending architecture v3 and legal approval**. In all materials, never state token value, price, returns, or investment.

---

## 6. End-to-end business process — “Run one AI task”

Use this as the baseline **happy path** for swimlanes, user stories, and acceptance criteria.

### 6.1 Swimlane summary

| Step | Customer | Platform (control plane) | Worker device | Finance / ledger |
| --- | --- | --- | --- | --- |
| 1 | Submit task + input file (free or token-backed credit) | Validate input & policy; check credit balance | — | — |
| 2 | See **credits this task uses** (no price) | **Quick assessment**: non-malicious check, difficulty class K, expected time | — | — |
| 3 | Confirm task | Reserve K × base credits; enter queue | — | — |
| 4 | — | Select **at least 3** eligible workers; reserve capacity; create **lease + fence** per worker | Receive **assignment** (signed) | Release X tokens for the task |
| 5 | Optional progress via portal/webhook | Track lifecycle events | Execute if consent & safety OK | — |
| 6 | — | **Consensus**: compare results; if no agreement, add 2 new workers (max 10 rounds) | Submit result / failure evidence | — |
| 7 | Receive validated result | Deliver webhook / portal | — | Deduct credit once; reward agreeing workers; treasury share |
| 8 | — | If edge unavailable and policy allows: **cloud fallback** with recorded reason | — | Recorded |

### 6.2 Business rules (must hold in requirements)

| ID | Rule | Rationale |
| --- | --- | --- |
| BR-01 | **No price shown to customers.** Credits used (K × base task) are fixed once the assessment is issued | Customer-facing rule; predictable credit use |
| BR-02 | **Only the platform** schedules, retries, reassigns, and decides cloud fallback | Prevents worker-side orchestration and fraud |
| BR-03 | Worker **does not accept/reject** individual tasks in production protocol | Opt-in + availability is the consent model |
| BR-04 | **Exactly one** accepted completion and **one** credit deduction per task revision | Credit integrity |
| BR-05 | **Exactly one** reward per agreeing worker per task; non-agreeing workers get nothing | Payout integrity |
| BR-06 | Cloud fallback **never silent** | Compliance and customer trust |
| BR-07 | Worker rewards are **variable, not guaranteed** | Legal / worker terms |
| BR-08 | Platform is **not crypto mining** | Worker terms and marketing guardrails |
| BR-09 | Temporary customer inputs **deleted within 15 minutes** | Privacy by design |
| BR-10 | **No token price, value, return, or investment claims** in any material | White paper disclaimer; [canonical-decisions.yaml](../../production/canonical-decisions.yaml) |
| BR-11 | Every task goes to **at least 3 workers**; result accepted only on consensus (≥ 2 of 3, or a majority in extended rounds, max 10 rounds) | Trusted results |
| BR-12 | Reward split per task: 3/3 agree → 25% of X each + 25% treasury; 2/3 → 25% each + 50% treasury; extended rounds → 75% split equally among agreeing workers + 25% treasury | White paper §7 |
| BR-13 | Cheating or lazy workers are warned, then **removed automatically** on repetition | Network integrity |

### 6.3 Exception paths (BA should model)

| Exception | Expected platform behavior | Customer-visible outcome |
| --- | --- | --- |
| No eligible worker | Queue, retry, or cloud fallback (if policy allows) | Delay or fallback with reason |
| Worker loses consent mid-run | Pause / terminate; server reassigns or fails | Task state + audit event |
| No consensus | Add 2 new workers per round, up to 10 rounds | Delay; after 10 rounds returned without result |
| Verification fails | Retry classification per policy; escalation tiers | Failed or escalated status |
| Credit exhausted | Reject submission; offer monthly token-backed credit | Clear message (no price) |
| Assessment expired before confirm | Reject confirm; new assessment required | Clear error |
| Unsupported worker country | Earning disabled for worker; task may still run on other workers | N/A to customer |
| Duplicate submission (idempotency) | Same logical task identity | No double bill |

---

## 7. Product catalog (business view)

Customers choose a **task type** from the catalog. Examples:

| Category | Example task types | Typical input |
| --- | --- | --- |
| Document intelligence | Document OCR, structured extract, verify | PDF, image |
| Vision & catalog | Image classify, tagging, safety checks, background removal | Image |
| Language & NLP | Summarize, translate, moderate, article help | Text |

**Important for BA:**

- Catalog lists **56 types**; implementation maps many types onto shared **pipelines** on the worker (OCR + on-device LLM + vision).
- **No prices are published or shown.** Each task uses **K × base task** credits, where K is the difficulty class from the quick assessment.
- **Accuracy** of OCR on real-world receipts is a **separate acceptance** from “API returns valid JSON.”

---

## 8. Commercial model

Full detail: [FibonAI-Business-Model.md](../business/FibonAI-Business-Model.md) §5–§8.

### 8.1 Customer side

| Element | Business model | Current build (GA1, frozen docs) |
| --- | --- | --- |
| What the customer sees | **Credits only** — free requests left this month, credits a task uses. **No price** | EUR quote before run |
| Free tier | A set number of free task requests per month; launch offer 1 month free + free API | — |
| Beyond free | Monthly credit (more or unlimited requests) via FibonAI token / account subscription | Prepaid EUR compute credits, Stripe Billing |
| Credit per task | \(T = K \times T_{base}\) (difficulty class × base task) | PriceBook + quote modifiers |
| Precision | Integer units; no floating point | Integer micro-EUR |

### 8.2 Worker side

| Element | Business model | Current build (GA1, frozen docs) |
| --- | --- | --- |
| Reward unit | **FibonAI tokens** for correct (consensus) answers | EUR Reward Micros (not a token) |
| Split per task | 25% of X per agreeing worker (3/3 or 2/3); 75% shared in extended rounds; rest to treasury | One worker credited once |
| Funding | 16 B participant pool on the IFPEM schedule; after it runs out, requester subscriptions | EUR liabilities, Stripe Connect |
| Messaging | Not guaranteed, not passive income, not mining | Same |

### 8.3 Token economy (summary)

21 B fixed supply, never minted again. 16 B to participants, released by the Infinite Fibonacci Power Emission Model (exponent 0.25), with about 1.88 B in year 1. 5 B to the parent investment company and token holders, released yearly on the same schedule. Treasury gets 25% of every reward release plus unused yearly emission; governance decides whether to burn it, fund development, or use it for staking support.

### 8.4 What never goes in customer or sales copy

- Any price per task (€, $ or tokens), rate tables, or quote amounts
- Token price, value forecasts, APY, returns, “investment”, or referral earnings from others’ tasks
- Guaranteed worker earnings or mining metaphors

Inviting others **to keep the network cycle going** is encouraged, without earnings claims.

---

## 9. Verification and quality (business tiers)

In the business model, **consensus is the default**: every task goes to at least 3 independent workers.

| Tier (concept) | Business meaning |
| --- | --- |
| Consensus (default) | At least 3 independent workers; anti-affinity rules; up to 10 rounds of +2 workers |
| Standard (current build default) | Single verified result path |
| Human review | Escalation when automated verification is insufficient |

Requirements should tie **verification outcome** to **credit deduction**, **reward split** and **audit events**.

---

## 10. Channels and touchpoints

| Channel | User | Primary actions |
| --- | --- | --- |
| Customer portal | Business user | Create task, see credits, monitor status, audit |
| REST API | Integration | Idempotent create, assessment, lifecycle, webhooks |
| Worker mobile app | Worker | Opt-in, availability, run assigned work, view token earnings |
| Operations portal | Internal staff | Investigate tasks, workers, fraud, credits and rewards |
| Marketing site | Prospect | Positioning, waitlist, worker APK download, portal entry — **no prices** |
| Webhooks / SSE | Customer systems | Event-driven integration |

---

## 11. Compliance and messaging guardrails

Use this checklist when reviewing user stories, copy, or partner decks:

- [ ] **No price** (€, $, tokens) shown to customers — credits only
- [ ] Credits a task uses shown **before** run confirmation
- [ ] Fallback reason **visible** when cloud used
- [ ] Worker copy includes **variable / not guaranteed** rewards
- [ ] No **token value, investment, returns** or **mining** language
- [ ] Token disclaimer included wherever tokens are mentioned (business model §11.4)
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
| Token business model | **Not implemented.** Frozen docs disable tokens; needs architecture v3 + legal sign-off |
| Customer portal prices | Current portal still shows internal EUR quotes; hiding them is open work |

Treat customer-facing SLAs as **blocked** until production gate and agreed UAT sign-off.

---

## 13. Glossary (business language)

| Term | Business meaning |
| --- | --- |
| **Task** | Customer’s request to run one unit of AI work (stable identity) |
| **Revision** | Immutable version of inputs/settings for that task |
| **Assessment** | Quick estimate of difficulty class K and time; fixes credits a task uses (current build: internal EUR quote, never shown) |
| **Consensus** | Agreement between independent workers' results; the only way a result is accepted |
| **Base task / K** | Unit of credit; a task of difficulty K uses K base tasks |
| **FibonAI token** | Network token (21 B fixed supply) for worker rewards and requester credit — no guaranteed value |
| **Treasury** | Community-governed reserve receiving 25% of each reward release |
| **Policy hash** | Fingerprint of execution policy for audit/replay |
| **Assignment** | Platform’s instruction for one worker to execute one attempt |
| **Lease / fence** | Exclusive right to execute; fence prevents stale workers overwriting results |
| **Verification** | Platform decision that result meets quality/integrity rules |
| **Cloud fallback** | Running on approved cloud when edge cannot meet policy/SLA |
| **Task credit** | Customer allowance: free monthly requests plus token-backed monthly credit (current build: prepaid EUR balance) |
| **Reward micros** | Current build only: worker payable EUR amount, not a token |
| **Workspace** | Customer tenancy boundary for data and billing |
| **Edge / worker** | Opted-in device executing signed models |
| **GA1** | First commercial release scope per canonical decisions |

Full definitions: [glossary.md](../00-executive/glossary.md).

---

## 14. Suggested BA deliverables from this brief

| Deliverable | Suggested content |
| --- | --- |
| **Context diagram** | Customer, Worker, Operator, Treasury, Exchanges, Cloud provider |
| **BPMN** | §6 happy path + §6.3 exceptions (including consensus rounds) |
| **Stakeholder map** | §4 + RACI for assessment, consensus, rewards, treasury |
| **Requirements backlog** | Trace BR-01…BR-13 to epics |
| **Data dictionary** | Task, Assessment, Assignment, Result, Consensus, Credit, Reward, Ledger event |
| **Gap analysis** | Business model vs frozen GA1 docs (business model §12) |
| **Compliance matrix** | Map BR rules to legal docs in `docs/09-legal/` |

---

## 15. Related documents

| Document | Use when |
| --- | --- |
| [FibonAI-Business-Model.md](../business/FibonAI-Business-Model.md) | Business model from the white paper (credits, consensus, tokens, governance) |
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
| 1.1 | 2026-11-17 | Updated from the FibonAI white paper | No customer-facing prices; credit + token model; 3-worker consensus; BR-11…BR-13 |
