# FibonAI — Discord & Telegram Client Acquisition Strategy

| Field | Value |
| --- | --- |
| Goal | Get businesses and developers to send their AI tasks to FibonAI, so the work can be shared with contributor phones |
| Main offer | **1 month free + free API access** |
| Channels | Telegram (reach and announcements), Discord (developer community and support) |
| Posts in this plan | 24: video, text, carousel/slider, photo, interactive |
| Run length | 4 weeks, 6 posts per week |
| Version | 2.0 — 2026-10-28 |

> **Before publishing, two approvals are needed.**
> 1. **Offer terms:** the business has to set the limits of the free month — the number of free tasks, which task types are included, and API rate limits. This plan uses `[N]` where that number goes.
> 2. **Token wording:** the repo still records tokens as disabled for the first release (`production/canonical-decisions.yaml`: `token.enabled: false`). Client posts mention the token only once, as an optional way to unlock more monthly tasks. Get legal approval before publishing that wording.

---

## 1. Who we are talking to

| Audience | What they need | What we say to them |
| --- | --- | --- |
| **Startups and indie developers** | Cheap AI for an MVP, without managing GPUs | "Ship your AI feature this week. One API call, first month free." |
| **Operations and back-office teams** | Read invoices, receipts and forms; sort documents | "Stop typing invoices by hand. Send the files, get structured data back." |
| **E-commerce teams** | Tag product photos, remove backgrounds, find duplicates and blurry images | "Clean up your whole catalog without a design team." |
| **Agencies and freelancers** | Batch work for many clients, predictable cost | "See the cost before the job runs." |
| **Content and support teams** | Summarise and classify long texts and tickets | "Summaries and labels, sent back to your system automatically." |

## 2. The offer

**Headline:** *Your first month is on us — free tasks and free API access.*

What a new client gets for the first month:

- `[N]` free tasks every month, starting on day one.
- A free API key, so they can connect FibonAI to their own app or backend straight away.
- Webhooks, so results are sent to their system automatically when a task finishes.
- A cost estimate before every task runs, so nothing is charged by surprise.
- Help from the team in a private Discord channel during setup.

After the first month, the free monthly tasks continue. Clients who need more can unlock extra monthly credit (optionally with FibonAI tokens, once that is approved).

**Why clients can trust it (proof points to repeat):**

1. **Estimate first.** Every task gets a quick check of difficulty and time before it runs.
2. **Real devices.** The work runs on a network of opted-in phones.
3. **Verified results.** Answers are checked before they are returned.
4. **Privacy.** The client's identity is never shown to the phones doing the work.
5. **Built for developers.** API keys, webhooks, idempotency keys (a safe retry never runs the same task twice).

## 3. The five-step flow (client version)

| Step | What the client sees |
| --- | --- |
| 1 · Free tasks | Sign up and get `[N]` free tasks plus a free API key |
| 2 · Quick estimate | Send a file or text; FibonAI checks how hard it is and how long it will take |
| 3 · Sent to the network | The task goes out to available phones as soon as possible |
| 4 · Processed | Phones run the task; contributors are rewarded for correct work |
| 5 · Verified result | FibonAI checks the answers and returns the correct one by API, webhook or dashboard |

**Pinned one-liner:**
> Send a task → get a quick estimate → real phones do the work → you get a verified result. First month free, API included.

## 4. What each platform is for

| | Telegram | Discord |
| --- | --- | --- |
| **Role** | Reach: offers, use cases, demos, countdowns | Depth: developer help, onboarding, feedback, case studies |
| **Setup** | Channel `@FibonAI` + linked group `FibonAI Builders` | Server for developers and client teams |
| **Best formats** | Short video, photo + caption, album slider, polls | Threads, code snippets, live demos, office hours |
| **Main CTA** | "Claim your free month" (sign-up link) | "Get your API key" + `#onboarding` channel |

### 4.1 Discord server layout

```text
START HERE
  #welcome            — the offer + how to claim it
  #claim-free-month   — sign-up link and steps; bot assigns the Builder role
  #announcements
BUILD
  #quickstart         — first API call in 5 minutes
  #api-help           — questions answered by the team
  #show-what-you-built
  #feature-requests
USE CASES
  #documents-ocr  #catalog-images  #text-summaries
EVENTS
  Stage: Office Hours (weekly), Live Demo (bi-weekly)
PRIVATE (per client)
  #onboarding-<company>  — created for teams in the free month
```

### 4.2 Client roles

| Role | How you get it | Unlocks |
| --- | --- | --- |
| **Visitor** | Join the server | Read and ask questions |
| **Builder** | Claim the free month | `#api-help` priority, quickstart files |
| **Shipped** | Post a working integration in `#show-what-you-built` | Featured in the weekly recap, early access to new task types |
| **Partner** | Active team after the free month | Private channel, roadmap calls |

---

## 5. Four-week calendar

| Week | Theme | Goal |
| --- | --- | --- |
| 1 | **The problem**: AI is expensive and slow to set up | Recognition: "that's me" |
| 2 | **The offer**: 1 month free + free API | Sign-ups |
| 3 | **Use cases**: documents, catalogs, text | "I can use this for X" |
| 4 | **Proof and urgency**: demos, client stories, deadline | Convert visitors into active clients |

Post on Telegram first, mirror to Discord `#announcements` within an hour, then start a discussion thread on Discord. Best times: weekdays, late morning and early evening in the audience's time zone.

Format key: 🎬 video · 🖼 photo · 🎠 carousel/slider · ✍️ text · 📊 interactive

---

## 6. The 24 posts

### Week 1 — The problem

---

#### P01 · 🎬 Video · Teaser — both platforms

- **Asset:** `FibonAI-Waitlist-Teaser-social.mp4` (15 s), rendered by `docs/brand/waitlist-video/render_waitlist.py`.
- **Caption:** AI shouldn't need a GPU budget. Something new is coming for teams who just want the job done. 👀
- **CTA:** Turn on notifications.

---

#### P02 · 🖼 Photo · The hidden cost — Telegram

- **Visual:** a stack of paper invoices next to a laptop showing a cloud bill; gold highlight on the bill total (no real figure).
- **Caption:** Typing invoices by hand costs hours. Running your own AI servers costs a fortune. There's a third option.
- **CTA:** Reply with the task that eats most of your week.

---

#### P03 · 📊 Poll · The pain — both platforms

- **Question:** What slows your team down the most?
  - Typing data from documents
  - Tagging and cleaning product photos
  - Reading long texts and tickets
  - Setting up AI infrastructure
- **Follow-up (next day):** share the result and say "We built FibonAI for exactly this. Offer reveal on Monday."

---

#### P04 · ✍️ Text · "3 ways to add AI to your product" — Discord thread + Telegram

- **Copy:**
  > 1️⃣ Build your own: GPUs, MLOps, weeks of setup.
  > 2️⃣ Big cloud AI: fast to start, bills grow quickly.
  > 3️⃣ FibonAI: send a task, see the estimate, get a verified result from a network of real devices.
  >
  > Option 3 is about to get a free first month.

---

#### P05 · 🎠 Carousel · "What can you send?" — Telegram album (6 slides)

| Slide | Visual | Text |
| --- | --- | --- |
| 1 | Gold "TASK" on a dark canvas | What can you send to FibonAI? |
| 2 | Invoice → structured fields | Read invoices, receipts and forms |
| 3 | Pile of documents → labelled folders | Classify and summarise documents |
| 4 | Product photo → clean cut-out | Remove backgrounds |
| 5 | Photo grid with tags and flags | Tag images, catch blurry photos and duplicates |
| 6 | Long text → 3 bullets | Summarise and label text |

---

#### P06 · 🎬 Video · Founder / host intro (15 s) — both platforms

- **Format:** 9:16 talking head (real founder or AI host). Say the name as "fee-boo-NIGH".
- **Script:** "Most teams want AI results, not AI infrastructure. At FibonAI you send a task, see the estimate first, and get a verified result back from our device network. On Monday we're opening something special for the first teams."
- **Shots:** medium close-up → hands typing on a laptop, API response appears → back to host.

---

### Week 2 — The offer

---

#### P07 · 🖼 Photo · Offer reveal — both platforms (pin this)

- **Visual:** large gold "1 MONTH FREE" in Cal Sans, smaller "+ free API access" in steel, chip frame from the homepage hero sequence (`src/apps/marketing-site/public/hero-sequence/desktop/`) behind it.
- **Caption:** It's here. Your first month on FibonAI is free: `[N]` tasks, a free API key and webhooks included. No setup fees, no servers.
- **CTA:** Claim your free month → link.

---

#### P08 · 🎠 Carousel · "What's included" — both platforms

| Slide | Text |
| --- | --- |
| 1 | Your free month includes… |
| 2 | `[N]` free tasks from day one |
| 3 | A free API key: connect your app in minutes |
| 4 | Webhooks: results sent to your system automatically |
| 5 | A cost estimate before every task |
| 6 | Team support in Discord while you set up |
| 7 | Claim it now: link in the pinned post |

---

#### P09 · 🎬 Video · "Your first API call" screen recording (20 s) — Discord + Telegram

- **Content:** a screen capture: create an API key in the dashboard → send one request → the estimate appears → the result arrives by webhook.
- **Caption:** From sign-up to first result in under 5 minutes. This is the whole setup.
- **Pinned snippet in `#quickstart`:** use the real request from the API docs (`docs/04-api/`); do not publish a made-up endpoint.

---

#### P10 · ✍️ Text · "How to claim in 3 steps" — both platforms

- **Copy:**
  > 1. Sign up with your work email.
  > 2. Open the dashboard → API Keys → create your free key.
  > 3. Send your first task. The estimate shows before anything runs.
  >
  > Stuck? Ask in `#api-help`; the team answers fast.

---

#### P11 · 🎬 Video · The flow in 10 seconds — both platforms

- **Concept:** a file drops in → two gold gauges (difficulty, time) fill → light trails go out to phones → answers come back, two match and glow → a verified result lands on a laptop.
- **Caption:** Send → estimate → processed on real devices → checked → returned. That's FibonAI.
- **Veo prompt:**
  ```text
  10-second premium motion graphics, dark charcoal background (#0B0C0F), champagne-gold glow (#CDAE6F) and steel-blue accents (#A6C0CB). A frosted-glass document card floats in; two thin gold gauges with mountain and clock icons fill; the card splits into soft gold light trails that travel to three modern phones on a dark surface; three small answer cards return, two glow teal (#19C7B4) and merge, then fly to a laptop screen with a soft check pulse. Smooth easing, shallow depth of field, no readable text, no logos.
  ```

---

#### P12 · 📊 Interactive · "What would you build?" — Discord

- **Copy:** You have a free month and a free API key. What's the first thing you'd build? Best idea gets a 30-minute setup call with the team and a feature in the weekly recap.
- **Format:** Discord forum post; each reply becomes a thread.

---

### Week 3 — Use cases

---

#### P13 · 🎠 Carousel · Use case: invoices and receipts — both platforms

| Slide | Text |
| --- | --- |
| 1 | 500 invoices. Zero typing. |
| 2 | Upload images or PDFs |
| 3 | FibonAI reads the text and pulls out fields: supplier, date, total |
| 4 | Results come back as structured data by API or webhook |
| 5 | Try it on your own invoices: first month free |

---

#### P14 · 🖼 Photo · Before / after background removal — Telegram

- **Visual:** a split image: product on a messy desk | the same product on clean white.
- **Caption:** Left: what your phone camera gives you. Right: what your store needs. Send the whole catalog in one batch.
- **CTA:** Try it free this month.

---

#### P15 · 🎬 Video · Catalog clean-up (12 s) — both platforms

- **Concept:** a grid of 30 product photos; blurry ones get a red flag, duplicates are linked, the rest get gold tags.
- **Caption:** Find blurry photos, duplicates and missing tags across your whole catalog in one run.

---

#### P16 · ✍️ Text · Use case: support tickets — Discord `#text-summaries` + Telegram

- **Copy:**
  > Your support inbox gets 300 messages a day.
  > FibonAI can summarise each one and label it: billing, bug, question, urgent.
  > Your team reads the summary, not the whole thread.
  > Send the text by API; results come back to your helpdesk by webhook.

---

#### P17 · 🎠 Carousel · "Why FibonAI and not just a big AI API?" — both platforms

| Slide | Text |
| --- | --- |
| 1 | Why FibonAI? |
| 2 | **See the cost first.** Every task is estimated before it runs |
| 3 | **Verified answers.** Results are checked before you get them |
| 4 | **Private by design.** Your identity is never shown to the devices |
| 5 | **No infrastructure.** No GPUs, no servers, no model hosting |
| 6 | **Free to start.** 1 month free, API included |

Do not name or attack competitors; compare against "running it yourself" or "typical cloud AI".

---

#### P18 · 🖼 Photo · Developer quote card — both platforms

- **Visual:** a dark card with a gold quote mark and a short quote from a real beta user, with their permission.
- **Placeholder copy (replace with a real quote; never invent one):** "We connected the API in an afternoon and sent our first 1,000 receipts the same day." — Name, Company
- **Caption:** Built something with FibonAI? Share it in `#show-what-you-built`.

---

### Week 4 — Proof and urgency

---

#### P19 · 🎙 Event · Live demo — Discord Stage + Telegram voice chat

- **Graphic:** a dark card with a gold play icon: "Live Demo · Thursday".
- **Copy:** Watch us take a real batch of documents from upload to verified result, live. Bring your own use case and we'll show you how to set it up.
- **Follow-up:** post the recording on both platforms the next day.

---

#### P20 · ✍️ Text · Case study thread — Discord + Telegram

- **Structure:** (use a real beta client, with permission)
  > **The team:** what they do.
  > **The problem:** the manual work.
  > **The setup:** which task types, API or dashboard, how long it took.
  > **The result:** time saved, tasks processed (real numbers only).
- **CTA:** Want the same setup? Claim your free month.

---

#### P21 · 📊 Poll · "Which task type next?" — both platforms

- **Question:** Which new task type should we add first?
  - Table extraction from PDFs
  - Multi-language OCR
  - Product description writing
  - Audio transcription
- **Purpose:** shows clients they shape the roadmap; feeds product planning. Label results as "requests", not promises.

---

#### P22 · 🖼 Photo · Countdown "7 days left" — both platforms (repeat at 3 days and 1 day)

- **Visual:** a large gold "7" over the chip frame, with "days left to claim your free month".
- **Caption:** The free first month is for early teams only. 7 days left to claim it.
- **Note:** only use a deadline if the offer really ends; otherwise use "Limited to the first `[X]` teams".

---

#### P23 · 🎬 Video · Office hours clip (30 s) — Discord + Telegram

- **Content:** the best 30 seconds from office hours where the team solves a real setup question.
- **Caption:** Every week we help teams connect FibonAI live. Next session: Thursday in Discord.

---

#### P24 · 🎬 Video · Launch recap (20 s) — both platforms

- **Edit:** chip close-up (homepage hero frames, 3 s) → flow animation (P11, 6 s) → use-case flashes: invoice, product photo, ticket (2 s each) → end card "1 MONTH FREE + FREE API".
- **Caption:** Documents, images, text: send the task, see the estimate, get a verified result. Your first month is free and the API is included.
- **CTA:** Claim your free month → link.

---

## 7. Recurring formats (after the 24 posts)

| Format | Day | Platform | Content |
| --- | --- | --- | --- |
| **Use case of the week** | Monday | Both | One task type in a 4-slide carousel |
| **Office hours** | Thursday | Discord Stage | 30 minutes, live setup help |
| **Shipped this week** | Friday | Both | Integrations clients posted in `#show-what-you-built` |
| **Changelog** | When something ships | Both | New task types, API changes |
| **Weekly recap** | Sunday | Telegram | What's new, top question, client highlight |

## 8. Moving clients from free to active

| Moment | Action |
| --- | --- |
| Sign-up | Bot gives the Builder role and links `#quickstart` |
| Day 2, no API call yet | Team member offers help in their onboarding channel |
| First result | "Nice! Here are 3 more task types you can try" |
| Day 21 | Message about what happens after the free month: free monthly tasks continue, more credit can be unlocked |
| Day 30 | Invite to Partner role if they stay active |

## 9. What to measure

| Metric | Week 1 target | Week 4 target |
| --- | --- | --- |
| Telegram channel subscribers | 500 | 3,000 |
| Discord members | 200 | 1,200 |
| Free-month sign-ups | — | 300 |
| Sign-ups who made a first API call | — | 40% |
| Tasks sent by free-month clients | — | 10,000 |
| Clients active after the free month | — | 25% |

Targets are starting assumptions; adjust after week 2. Task volume from clients is the number that matters most, because it is the work shared with contributor phones.

## 10. Copy rules

| Say | Don't say |
| --- | --- |
| "First month free" (with the real limits in the terms) | "Unlimited", "free forever" |
| "See the cost before it runs" | Exact prices, unless they are the current published rates |
| "Verified results" | "100% accurate", "instant" |
| "Your identity is never shown to the devices" | "Fully anonymous", "no one ever sees your data" |
| Real client quotes and numbers, with permission | Made-up testimonials or statistics |
| "Optionally unlock more tasks with FibonAI tokens" (after legal approval) | Token price, value, investment, mining |

## 11. Production checklist

| Asset | Status | Source |
| --- | --- | --- |
| Teaser video (P01) | Render before posting | `docs/brand/waitlist-video/render_waitlist.py` |
| Chip stills | Ready | `src/apps/marketing-site/public/hero-sequence/desktop/` (144 frames exported from `Scroll.mp4`; the source video is not kept) |
| Logo, palette, fonts | Ready | `docs/brand/DESIGN.md` |
| Offer reveal video (P07) | Render before posting | `render_social.py --video 1` → `FibonAI-01-Free-Month-*.mp4` |
| Flow animation (P11) | Render before posting | `render_social.py --video 2` → `FibonAI-02-How-It-Works-*.mp4` |
| Verification video (P16, P17) | Render before posting | `render_social.py --video 3` → `FibonAI-03-Verified-By-3-Phones-*.mp4` |
| Invoice use-case video (P13) | Render before posting | `render_social.py --video 4` → `FibonAI-04-Invoices-*.mp4` |
| Catalog use-case video (P14, P15) | Render before posting | `render_social.py --video 5` → `FibonAI-05-Catalog-Cleanup-*.mp4` |
| API screen recording (P09) | To produce | Real dashboard + real API request from `docs/04-api/` |
| Carousels | To design | 1080×1350 for Telegram albums, 1920×1080 for Discord |
| Client quote and case study (P18, P20) | Needs a real beta client | Written permission required |
| Free-month terms (`[N]` tasks, limits, end date) | **Business decision needed** | — |
| Token wording approval | **Legal approval needed** | `docs/09-legal/` |

The five videos come in `16x9` (Discord) and `9x16` (Telegram stories, vertical feeds) versions, 13–15 seconds each, with a soundtrack generated by the render script. The rendered MP4s are not kept in the repository; render them into `docs/brand/social-videos/` with `python docs/brand/social-videos/render_social.py --video all --ratio both --jobs 5`. Video 3 uses the white paper's verification model (each task sent to 3 phones, matching answers accepted, cheating phones warned and then removed); confirm it matches the production verification policy before publishing.

**Visual style:** dark canvas `#0B0C0F`, gold `#CDAE6F`, gold soft `#F1E6CF`, steel `#A6C0CB`, verified teal `#19C7B4`; Cal Sans for headlines, Geist Sans for body text, Geist Mono for code and API snippets.
