<script setup>
import { computed } from 'vue';
import { RouterLink } from 'vue-router';

import HeroVisual from '../components/HeroVisual.vue';
import {
  capabilityChips,
  fanTargets,
  hero,
  integrations,
  portalFields,
  portalNav,
  pricingRows,
  quoteSample,
  taskCards,
  taskFeed,
  useCaseGroups,
} from '../content/site.js';
import '../home.css';

const heroTitle = computed(() => {
  const [before, after = ''] = hero.title.split(hero.titleHighlight);
  return { before, highlight: hero.titleHighlight, after };
});

const useCaseGlyphs = ['▤', '◎', '¶', '⧉'];

function trackPointer(event) {
  const card = event.target.closest?.('.em-card');
  if (!card) return;
  const rect = card.getBoundingClientRect();
  card.style.setProperty('--mx', `${event.clientX - rect.left}px`);
  card.style.setProperty('--my', `${event.clientY - rect.top}px`);
}
</script>

<template>
  <div class="em-home" @pointermove="trackPointer">
    <section class="hero hero--command">
      <div class="hero__scene" aria-hidden="true"></div>
      <div class="container hero__grid">
        <div class="hero__inner">
          <h1 class="hero__title">
            {{ heroTitle.before }}<span class="em-highlight">{{ heroTitle.highlight }}</span>{{ heroTitle.after }}
          </h1>
          <p class="hero__subtitle">{{ hero.subtitle }}</p>
          <div class="hero__actions">
            <RouterLink class="em-pill em-pill--solid" :to="{ name: hero.primaryCta.to }">
              {{ hero.primaryCta.label }} <span class="em-pill__chev">›</span>
            </RouterLink>
            <RouterLink class="em-pill em-pill--ghost" :to="{ name: hero.secondaryCta.to }">
              {{ hero.secondaryCta.label }} <span class="em-pill__chev">›</span>
            </RouterLink>
          </div>
        </div>
        <div class="hero__visual">
          <HeroVisual />
        </div>
      </div>
    </section>

    <section v-reveal class="em-section">
      <div class="container">
        <p class="em-eyebrow">Quote engine</p>
        <h2 class="em-title">Price First.<br />Run Second.</h2>

        <article class="em-card em-card--feature em-card--split">
          <div class="em-card__lead">
            <p class="em-gradient-text" aria-hidden="true">Quote.<br />Route.<br />Verify.</p>
            <span class="sr-only">Quote, route, verify.</span>
          </div>
          <ol class="em-feed" aria-label="Recent task activity">
            <li v-for="item in taskFeed" :key="`${item.task}-${item.file}`" class="em-feed__row">
              <span class="em-feed__node" aria-hidden="true"></span>
              <span class="em-feed__avatar" aria-hidden="true">{{ item.task.split('.')[0].slice(0, 2) }}</span>
              <span class="em-feed__text">
                <strong>{{ item.task }} · {{ item.file }}</strong>
                <small>{{ item.meta }}</small>
              </span>
              <span class="em-feed__status" :class="`em-feed__status--${item.status}`" :aria-label="item.status === 'ok' ? 'Completed' : 'Held by policy'">
                {{ item.status === 'ok' ? '✓' : '✕' }}
              </span>
            </li>
          </ol>
        </article>

        <div class="em-grid em-grid--2">
          <article class="em-card em-card--panel">
            <pre class="em-code" aria-label="Sample quote"><code><span v-for="(line, index) in quoteSample" :key="index" class="em-code__line"><span class="em-code__no">{{ String(index + 1).padStart(2, '0') }}</span>{{ line }}</span></code></pre>
            <p class="em-card__caption"><strong>Immutable quotes.</strong> Amount, route, and policy hash are fixed before any worker starts.</p>
          </article>
          <article class="em-card em-card--panel">
            <div class="em-vault" aria-hidden="true">
              <span class="em-vault__lamp em-vault__lamp--a"></span>
              <span class="em-vault__lamp em-vault__lamp--b"></span>
              <span class="em-vault__lamp em-vault__lamp--c"></span>
              <span class="em-vault__lock">⛨</span>
            </div>
            <p class="em-card__caption"><strong>Audit trail.</strong> Every attempt, revision, and billing event stays in the ledger.</p>
          </article>
        </div>
      </div>
    </section>

    <section v-reveal class="em-section em-section--tight">
      <div class="container">
        <h2 class="em-title em-title--sm">Everything A Regulated Team Needs.</h2>
        <ul class="em-chips" aria-label="Platform capabilities">
          <li v-for="chip in capabilityChips" :key="chip.label">
            <span aria-hidden="true">{{ chip.icon }}</span>{{ chip.label }}
          </li>
        </ul>
      </div>
    </section>

    <section v-reveal class="em-section">
      <div class="container">
        <div class="em-intro">
          <div>
            <p class="em-eyebrow">Customer portal</p>
            <h2 class="em-title">Start In The Portal.<br />No Setup Required.</h2>
            <p class="em-lead">Upload a file, pick a task type, and see the EUR quote before you confirm. Move to the API when you are ready.</p>
          </div>
          <div class="em-selects" aria-hidden="true">
            <div class="em-select">
              <span class="em-select__icon">▤</span>
              <span class="em-select__text"><small>Task type</small>document.ocr</span>
              <span class="em-select__chev">⌄</span>
            </div>
            <div class="em-select em-select--offset">
              <span class="em-select__icon">⌖</span>
              <span class="em-select__text"><small>Region</small>EU only</span>
              <span class="em-select__chev">⌄</span>
            </div>
          </div>
        </div>

        <article class="em-card em-card--feature em-card--split em-card--blue">
          <div class="em-card__lead">
            <p class="em-gradient-text em-gradient-text--blue" aria-hidden="true">Upload.<br />Quote.<br />Run.</p>
            <span class="sr-only">Upload, quote, run.</span>
            <div class="em-beam-row">
              <RouterLink class="em-pill em-pill--solid" :to="{ name: 'contact' }">
                Get access <span class="em-pill__chev">›</span>
              </RouterLink>
              <span class="em-beam" aria-hidden="true"></span>
            </div>
            <p class="em-card__body">Click to create a task, <strong>see the quote first</strong>, then run it on an <strong>edge worker</strong> with results and audit events in <strong>one workspace</strong>.</p>
          </div>
          <div class="em-window" aria-label="Customer portal preview">
            <div class="em-window__bar">
              <span></span><span></span><span></span>
              <em>portal · tasks / new</em>
            </div>
            <div class="em-window__body">
              <nav class="em-window__nav">
                <p>Workspace</p>
                <span v-for="(item, index) in portalNav" :key="item" :class="{ 'is-active': index === 0 }">{{ item }}</span>
              </nav>
              <div class="em-window__main">
                <p class="em-window__title">New task</p>
                <div v-for="field in portalFields" :key="field.label" class="em-window__field">
                  <small>{{ field.label }}</small>
                  <span>{{ field.value }}</span>
                </div>
                <div class="em-window__quote">
                  <span><small>Quote</small><strong>€0.0025</strong></span>
                  <span class="em-window__run">Run task</span>
                </div>
              </div>
            </div>
          </div>
        </article>

        <div class="em-grid em-grid--2">
          <article class="em-card em-card--panel em-card--blue-soft">
            <h3 class="em-card__heading">Portal or API</h3>
            <div class="em-mini">
              <pre class="em-code em-code--mini"><code><span class="em-code__line">POST /v1/tasks</span><span class="em-code__line">Idempotency-Key: 7c1e…</span><span class="em-code__line">{ "task_type": "document.ocr" }</span></code></pre>
              <div class="em-mini__list">
                <p>Delivery</p>
                <span><i></i>Webhook</span>
                <span><i></i>SSE events</span>
                <span><i></i>Portal</span>
              </div>
            </div>
            <p class="em-card__caption"><strong>Same task, two doors.</strong> Start in the portal, then call the public API with idempotent creates.</p>
          </article>
          <article class="em-card em-card--panel em-card--blue-soft">
            <h3 class="em-card__heading">One contract</h3>
            <div class="em-fan" aria-hidden="true">
              <span class="em-fan__source">API</span>
              <svg class="em-fan__lines" viewBox="0 0 300 160" preserveAspectRatio="none">
                <path d="M0 80 H110" />
                <path d="M150 80 C 200 80, 210 14, 290 14" />
                <path d="M150 80 C 200 80, 210 58, 290 58" />
                <path d="M150 80 C 200 80, 210 102, 290 102" />
                <path d="M150 80 C 200 80, 210 146, 290 146" />
              </svg>
              <span class="em-fan__hub">EM</span>
              <ul class="em-fan__targets">
                <li v-for="target in fanTargets" :key="target.label" :class="`em-fan__target--${target.tone}`">{{ target.label }}</li>
              </ul>
            </div>
            <p class="em-card__caption"><strong>Consistent results.</strong> Edge or cloud, every task returns the same result shape and writes the same ledger events.</p>
          </article>
        </div>
      </div>
    </section>

    <section v-reveal class="em-section">
      <div class="container">
        <p class="em-eyebrow">Edge network</p>
        <h2 class="em-title">Verified Devices.<br />Visible Fallback.</h2>
        <p class="em-lead">Opted-in phones run signed models close to the data. Cloud runs only when your policy allows, and the reason is recorded.</p>

        <article class="em-card em-card--feature em-card--split">
          <div class="em-card__lead">
            <p class="em-gradient-text" aria-hidden="true">Submit.<br />Assign.<br />Deliver.</p>
            <span class="sr-only">Submit, assign, deliver.</span>
            <RouterLink class="em-pill em-pill--solid" :to="{ name: 'how-it-works' }">
              See the workflow <span class="em-pill__chev">›</span>
            </RouterLink>
          </div>
          <div class="em-route" aria-label="Task routing">
            <p class="em-route__title">Task route</p>
            <div class="em-route__group">
              <span class="em-route__label">Inputs</span>
              <div class="em-route__chips">
                <span>document</span><span>image</span><span>text</span>
              </div>
            </div>
            <div class="em-route__group">
              <span class="em-route__label">Policy</span>
              <div class="em-route__chips">
                <span>region EU</span><span>SLA</span><span>tier</span>
              </div>
            </div>
            <div class="em-route__flow">
              <span class="em-route__node em-route__node--edge">Edge worker</span>
              <span class="em-route__line" aria-hidden="true"></span>
              <span class="em-route__check" aria-hidden="true"><span>✓</span></span>
              <span class="em-route__line" aria-hidden="true"></span>
              <span class="em-route__node">Result + audit</span>
            </div>
            <div class="em-route__flow em-route__flow--alt">
              <span class="em-route__node em-route__node--muted">Cloud fallback</span>
              <span class="em-route__note">only if policy allows · reason recorded</span>
            </div>
          </div>
        </article>

        <div class="em-grid em-grid--2">
          <article class="em-card em-card--panel em-card--text">
            <h3>Signed models</h3>
            <p>Workers check each model's SHA-256 and signature before execution.</p>
            <div class="em-orb" aria-hidden="true"><span>SHA-256</span></div>
          </article>
          <article class="em-card em-card--panel em-card--text">
            <h3>Opt-in workers</h3>
            <p>Devices run tasks only while their owner opts in. Rewards are variable, not guaranteed, and this is not crypto mining.</p>
            <div class="em-orb em-orb--ring" aria-hidden="true"><span>opt-in</span></div>
          </article>
          <article class="em-card em-card--panel em-card--text em-card--violet">
            <h3>Integrations</h3>
            <p>REST, server-sent events, signed webhooks, and a generated TypeScript client from the OpenAPI contract.</p>
            <div class="em-orbit" aria-hidden="true">
              <span class="em-orbit__core">EM</span>
              <span v-for="(item, index) in integrations" :key="item" class="em-orbit__item" :style="{ '--i': index }">{{ item }}</span>
            </div>
          </article>
          <article class="em-card em-card--panel em-card--text em-card--key">
            <h3>One-request quotes</h3>
            <p>Ask for a price before anything runs. The quote is fixed once issued.</p>
            <div class="em-keycap" aria-hidden="true"><span>Quote</span></div>
          </article>
        </div>
      </div>
    </section>

    <section v-reveal class="em-section">
      <div class="container em-glass-section">
        <div class="em-glass-section__copy">
          <h2 class="em-title em-title--xl">Your Data.<br />Your Region.<br />Your Policy.</h2>
          <p class="em-lead em-lead--bright">Workloads go only where your execution policy allows. Customer identity is never shown to workers, and temporary inputs are deleted within 15 minutes.</p>
          <div class="em-points">
            <div>
              <span aria-hidden="true">⌖</span>
              <h3>Region policies</h3>
              <p>Data region rules are enforced at intake, before a quote is issued.</p>
            </div>
            <div>
              <span aria-hidden="true">▤</span>
              <h3>Any input</h3>
              <p>Documents, images, text, and audio through one task lifecycle.</p>
            </div>
          </div>
        </div>
        <div class="em-glass" aria-hidden="true">
          <span class="em-glass__cone"></span>
          <span class="em-glass__torus"></span>
          <span class="em-glass__cube"></span>
        </div>
      </div>
    </section>

    <section v-reveal class="em-section">
      <div class="container">
        <p class="em-eyebrow">Use cases</p>
        <h2 class="em-title">One Platform For Documents, Vision, And Language.</h2>
        <div class="em-grid em-grid--4">
          <article v-for="(group, index) in useCaseGroups" :key="group.title" class="em-card em-card--tile" v-reveal="index * 80">
            <h3>{{ group.title }}</h3>
            <p>{{ group.items.join(' · ') }}</p>
            <div class="em-glow" aria-hidden="true"><span>{{ useCaseGlyphs[index] }}</span></div>
          </article>
        </div>
      </div>
    </section>

    <section v-reveal class="em-section">
      <div class="container">
        <p class="em-eyebrow">Pricing</p>
        <h2 class="em-title">Published Unit Rates<br />In EUR.</h2>

        <article class="em-card em-card--feature em-card--split">
          <div class="em-card__lead">
            <p class="em-gradient-text" aria-hidden="true">Know<br />Every<br />Cent.</p>
            <span class="sr-only">Know every cent.</span>
            <p class="em-card__body">Each production quote adds plan, priority, verification, and execution-policy modifiers to these base rates.</p>
            <RouterLink class="em-pill em-pill--solid" :to="{ name: 'pricing' }">
              View full pricing <span class="em-pill__chev">›</span>
            </RouterLink>
          </div>
          <div class="em-table" role="table" aria-label="Base rates">
            <div class="em-table__head" role="row">
              <span role="columnheader">Task</span>
              <span role="columnheader">Measure</span>
              <span role="columnheader">From</span>
            </div>
            <div v-for="row in pricingRows.slice(0, 5)" :key="row.task" class="em-table__row" role="row">
              <span role="cell">{{ row.task }}</span>
              <span role="cell"><em class="em-badge">{{ row.measure }}</em></span>
              <span role="cell"><strong>{{ row.price }}</strong></span>
            </div>
          </div>
        </article>
      </div>
    </section>

    <section v-reveal class="em-section">
      <div class="container">
        <p class="em-eyebrow">Task catalog</p>
        <div class="em-headrow">
          <h2 class="em-title">60+ Task Types.<br />One Contract.</h2>
          <RouterLink class="em-pill em-pill--ghost" :to="{ name: 'developers' }">Read the API</RouterLink>
        </div>
        <div class="em-catalog">
          <RouterLink
            v-for="(card, index) in taskCards"
            :key="card.title"
            class="em-card em-card--template"
            :to="{ name: card.to }"
            v-reveal="index * 80"
          >
            <span class="em-template__glyph" aria-hidden="true">{{ card.glyph }}</span>
            <h3>{{ card.title }}</h3>
            <p>{{ card.body }}</p>
            <small>{{ card.price }}</small>
            <span class="em-circle" aria-hidden="true">›</span>
          </RouterLink>
          <div class="em-catalog__aside">
            <p>Every task type ships with a published rate and a defined result contract.</p>
            <RouterLink class="em-link" :to="{ name: 'models' }">Explore task types <span aria-hidden="true">→</span></RouterLink>
          </div>
        </div>
      </div>
    </section>

    <section v-reveal class="em-section em-final">
      <div class="container em-final__inner">
        <h2 class="em-title em-title--center">Run Your First Task</h2>
        <p class="em-lead em-lead--center">Start in the customer portal, or talk to us about dedicated pools and region policies.</p>
        <RouterLink class="em-pill em-pill--solid" :to="{ name: 'contact' }">
          Request a demo <span class="em-pill__chev">›</span>
        </RouterLink>
        <div class="em-final__beam" aria-hidden="true"></div>
      </div>
    </section>
  </div>
</template>
