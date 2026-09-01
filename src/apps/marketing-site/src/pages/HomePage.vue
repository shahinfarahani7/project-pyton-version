<script setup>
import { RouterLink } from 'vue-router';

import CtaBand from '../components/CtaBand.vue';
import HeroVisual from '../components/HeroVisual.vue';
import SectionDivider from '../components/SectionDivider.vue';
import SectionHeading from '../components/SectionHeading.vue';
import TrustMarquee from '../components/TrustMarquee.vue';
import {
  flowSteps,
  hero,
  pillars,
  pricingRows,
  stats,
  useCaseGroups,
} from '../content/site.js';
</script>

<template>
  <div>
    <section class="hero">
      <div class="hero__glow" aria-hidden="true" />
      <div class="hero__spark hero__spark--1" aria-hidden="true" />
      <div class="hero__spark hero__spark--2" aria-hidden="true" />
      <div class="hero__spark hero__spark--3" aria-hidden="true" />

      <div class="container hero__grid">
        <div class="hero__inner">
          <p class="hero__eyebrow reveal is-visible">{{ hero.eyebrow }}</p>
          <h1 class="hero__title reveal is-visible" style="--reveal-delay: 80ms">{{ hero.title }}</h1>
          <p class="hero__subtitle reveal is-visible" style="--reveal-delay: 160ms">{{ hero.subtitle }}</p>
          <div class="hero__actions reveal is-visible" style="--reveal-delay: 240ms">
            <RouterLink class="btn btn--primary btn--lg" :to="{ name: hero.primaryCta.to }">
              {{ hero.primaryCta.label }}
            </RouterLink>
            <RouterLink class="btn btn--outline btn--lg" :to="{ name: hero.secondaryCta.to }">
              {{ hero.secondaryCta.label }}
            </RouterLink>
          </div>
          <div class="hero__panel reveal is-visible" style="--reveal-delay: 320ms">
            <div class="hero__panel-row">
              <span class="hero__chip">Quote received</span>
              <code>€0.0025 · document.ocr · edge-preferred</code>
            </div>
            <div class="hero__panel-row hero__panel-row--muted">
              <span>Task queued → worker assigned → result verified</span>
              <span class="hero__status">Live</span>
            </div>
          </div>
        </div>

        <div class="hero__visual reveal is-visible" style="--reveal-delay: 400ms">
          <HeroVisual />
        </div>
      </div>
    </section>

    <TrustMarquee />

    <section v-reveal class="section section--tight">
      <div class="container stat-strip">
        <div v-for="(item, index) in stats" :key="item.label" class="stat-strip__item" v-reveal="index * 80">
          <span class="stat-strip__icon" aria-hidden="true">{{ item.icon }}</span>
          <strong>{{ item.value }}</strong>
          <span>{{ item.label }}</span>
        </div>
      </div>
    </section>

    <SectionDivider label="Platform" />

    <section v-reveal class="section">
      <div class="container">
        <SectionHeading
          eyebrow="Why EdgeMint"
          title="Enterprise AI execution without the black box"
          subtitle="Built for teams that need predictable cost, policy-aware routing, and evidence for every inference decision."
        />
        <div class="card-grid card-grid--3">
          <article v-for="(item, index) in pillars" :key="item.title" class="feature-card feature-card--glow" v-reveal="index * 90">
            <span class="feature-card__icon" aria-hidden="true">{{ item.icon }}</span>
            <h3>{{ item.title }}</h3>
            <p>{{ item.body }}</p>
          </article>
        </div>
      </div>
    </section>

    <SectionDivider />

    <section v-reveal class="section section--alt">
      <div class="container">
        <SectionHeading
          eyebrow="Workflow"
          title="From upload to audit trail in four steps"
          subtitle="Async by design — integrate through the portal today or the public API when you are ready for production."
        />
        <ol class="flow-list">
          <li v-for="(step, index) in flowSteps" :key="step.step" class="flow-list__item" v-reveal="index * 100">
            <span class="flow-list__step">{{ step.step }}</span>
            <div>
              <h3>{{ step.title }}</h3>
              <p>{{ step.body }}</p>
            </div>
          </li>
        </ol>
        <div class="section__actions">
          <RouterLink class="btn btn--outline" :to="{ name: 'how-it-works' }">See full workflow</RouterLink>
        </div>
      </div>
    </section>

    <SectionDivider label="Solutions" />

    <section v-reveal class="section">
      <div class="container">
        <SectionHeading
          eyebrow="Use cases"
          title="One platform for document, vision, and language workloads"
        />
        <div class="card-grid card-grid--2">
          <article v-for="(group, index) in useCaseGroups" :key="group.title" class="use-case-card use-case-card--accent" v-reveal="index * 90">
            <span class="use-case-card__badge" aria-hidden="true">{{ index + 1 }}</span>
            <h3>{{ group.title }}</h3>
            <ul>
              <li v-for="item in group.items" :key="item">{{ item }}</li>
            </ul>
          </article>
        </div>
      </div>
    </section>

    <SectionDivider />

    <section v-reveal class="section section--alt">
      <div class="container container--narrow">
        <SectionHeading
          eyebrow="Pricing"
          title="Published unit rates in EUR"
          subtitle="Every production quote applies plan, priority, verification, and execution-policy modifiers on top of these base rates."
        />
        <div class="pricing-preview pricing-preview--glow" v-reveal="120">
          <table class="pricing-table">
            <thead>
              <tr>
                <th scope="col">Task</th>
                <th scope="col">Measure</th>
                <th scope="col">From</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in pricingRows.slice(0, 5)" :key="row.task">
                <td>{{ row.task }}</td>
                <td>{{ row.measure }}</td>
                <td><strong>{{ row.price }}</strong></td>
              </tr>
            </tbody>
          </table>
        </div>
        <div class="section__actions">
          <RouterLink class="btn btn--primary" :to="{ name: 'pricing' }">View full pricing</RouterLink>
        </div>
      </div>
    </section>

    <div v-reveal>
      <CtaBand
        title="Ready to run your first task?"
        body="Start in the customer portal for development, or talk to our team about enterprise deployment, dedicated pools, and region policies."
        cta-label="Request a demo"
      />
    </div>
  </div>
</template>
